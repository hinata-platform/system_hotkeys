import 'dart:async';
import 'dart:math';

import 'package:dbus/dbus.dart';

/// A shortcut as the portal reports it: what it does and, in the desktop's
/// own words, which keys trigger it. [trigger] is empty when the desktop
/// bound the id without keys, for instance because the suggested ones were
/// taken.
typedef PortalShortcut = ({String description, String trigger});

/// What the portal asks to have bound: an id's description and, optionally,
/// the keys the app suggests in the XDG shortcuts syntax (`CTRL+ALT+s`).
typedef PortalShortcutRequest = ({String description, String? trigger});

/// How a request ended, from `org.freedesktop.portal.Request::Response`.
enum PortalResponse {
  success,

  /// The person cancelled the system's dialog.
  cancelled,

  /// The request ended some other way: an error, or the session went away.
  ended,
}

/// The `org.freedesktop.portal.GlobalShortcuts` portal, version 1 and 2,
/// plus the host registry (`org.freedesktop.host.portal.Registry`) an app
/// outside a sandbox announces itself through.
///
/// Written against the upstream introspection XML, with what the XML does
/// not say made explicit:
///
/// * A call that takes a while answers with a `Request` object whose
///   `Response` signal carries the result. The client subscribes to the
///   path it can predict from its unique name and the `handle_token` before
///   it calls, so a fast answer is not missed; an old portal that answers on
///   another path is followed there.
/// * `CreateSession` returns the session handle as `s`, not `o`.
/// * `BindShortcuts` may bind any subset of what was asked, none included.
class GlobalShortcutsPortal {
  GlobalShortcutsPortal(this._client)
    : _portal = DBusRemoteObject(_client, name: busName, path: _path);

  final DBusClient _client;
  final DBusRemoteObject _portal;

  static const busName = 'org.freedesktop.portal.Desktop';
  static const _interface = 'org.freedesktop.portal.GlobalShortcuts';
  static const _registry = 'org.freedesktop.host.portal.Registry';
  static const _request = 'org.freedesktop.portal.Request';
  static const _session = 'org.freedesktop.portal.Session';
  static final _path = DBusObjectPath('/org/freedesktop/portal/desktop');

  /// Request and session tokens: unique within this connection, and random
  /// enough that a second process with the same connection name (after a
  /// restart of the bus) cannot collide with a stale one.
  final String _prefix = 'system_hotkeys_${Random().nextInt(1 << 30)}';
  int _tokens = 0;
  String _token() => '${_prefix}_${_tokens++}';

  /// Tells the portal which installed app this connection is: [appId] is
  /// the basename of the app's `.desktop` file, without the extension. Must
  /// come before any other portal call, and only once per connection. Fails
  /// for an app the portal sees as sandboxed (Snap, Flatpak), which it knows
  /// by its sandbox already, and on portals older than 1.20.
  Future<void> registerApp(String appId) => _portal.callMethod(
    _registry,
    'Register',
    [DBusString(appId), DBusDict.stringVariant(const {})],
    replySignature: DBusSignature(''),
  );

  /// The interface version; throws when the portal or its GlobalShortcuts
  /// interface is missing, as on desktops without a backend for it.
  Future<int> version() async => (await _portal.getProperty(
    _interface,
    'version',
    signature: DBusSignature('u'),
  )).asUint32();

  /// Opens a session. Shortcuts belong to a session and go with it.
  Future<String> createSession() async {
    final (code, results) = await _call(
      'CreateSession',
      (token) => [
        DBusDict.stringVariant({
          'handle_token': DBusString(token),
          'session_handle_token': DBusString(_token()),
        }),
      ],
    );
    final handle = results['session_handle'];
    if (code != PortalResponse.success || handle == null) {
      throw StateError('CreateSession ended with ${code.name}');
    }
    // `s` by the portal's own admission; `o` would be the correct type.
    return handle is DBusObjectPath ? handle.value : handle.asString();
  }

  /// Asks for [shortcuts] to be bound in [session]; the desktop may show a
  /// dialog first. Allowed once per session. Answers what it bound, which
  /// can be any part of what was asked.
  Future<(PortalResponse, Map<String, PortalShortcut>)> bindShortcuts(
    String session,
    Map<String, PortalShortcutRequest> shortcuts,
  ) async {
    final (code, results) = await _call(
      'BindShortcuts',
      (token) => [
        DBusObjectPath(session),
        DBusArray(DBusSignature('(sa{sv})'), [
          for (final MapEntry(key: id, value: s) in shortcuts.entries)
            DBusStruct([
              DBusString(id),
              DBusDict.stringVariant({
                'description': DBusString(s.description),
                if (s.trigger case final trigger?)
                  'preferred_trigger': DBusString(trigger),
              }),
            ]),
        ]),
        DBusString(''),
        DBusDict.stringVariant({'handle_token': DBusString(token)}),
      ],
    );
    return (code, parseShortcuts(results['shortcuts']));
  }

  /// Opens the desktop's own settings for the shortcuts of [session].
  /// Version 2 of the interface.
  Future<void> configureShortcuts(String session) => _portal.callMethod(
    _interface,
    'ConfigureShortcuts',
    [DBusObjectPath(session), DBusString(''), DBusDict.stringVariant(const {})],
    replySignature: DBusSignature(''),
  );

  /// Ends [session], which releases its shortcuts.
  Future<void> closeSession(String session) => DBusRemoteObject(
    _client,
    name: busName,
    path: DBusObjectPath(session),
  ).callMethod(_session, 'Close', const [], replySignature: DBusSignature(''));

  /// Presses: the session and the shortcut id.
  Stream<(String, String)> get activated => _signal(
    'Activated',
    'osta{sv}',
  ).map((s) => (s.values[0].asObjectPath().value, s.values[1].asString()));

  /// The desktop changed what triggers some shortcuts of a session, or what
  /// it says about them.
  Stream<(String, Map<String, PortalShortcut>)> get shortcutsChanged => _signal(
    'ShortcutsChanged',
    'oa(sa{sv})',
  ).map((s) => (s.values[0].asObjectPath().value, parseShortcuts(s.values[1])));

  Stream<DBusSignal> _signal(String name, String signature) => DBusSignalStream(
    _client,
    sender: busName,
    interface: _interface,
    name: name,
    path: _path,
    signature: DBusSignature(signature),
  );

  /// Calls [method] and waits for its `Response`. No timeout: the desktop
  /// may be showing the person a dialog.
  Future<(PortalResponse, Map<String, DBusValue>)> _call(
    String method,
    List<DBusValue> Function(String token) arguments,
  ) async {
    if (_client.uniqueName.isEmpty) await _client.ping();
    final token = _token();
    final sender = _client.uniqueName.substring(1).replaceAll('.', '_');
    final expected = DBusObjectPath(
      '/org/freedesktop/portal/desktop/request/$sender/$token',
    );
    final response = Completer<DBusSignal>();
    StreamSubscription<DBusSignal> listen(DBusObjectPath path) =>
        _responses(path).listen((signal) {
          if (!response.isCompleted) response.complete(signal);
        });
    var subscription = listen(expected);
    try {
      final reply = await _portal.callMethod(
        _interface,
        method,
        arguments(token),
        replySignature: DBusSignature('o'),
      );
      final handle = reply.returnValues.first.asObjectPath();
      if (handle != expected) {
        await subscription.cancel();
        subscription = listen(handle);
      }
      final signal = await response.future;
      final code = signal.values[0].asUint32();
      return (
        switch (code) {
          0 => PortalResponse.success,
          1 => PortalResponse.cancelled,
          _ => PortalResponse.ended,
        },
        signal.values[1].asStringVariantDict(),
      );
    } finally {
      await subscription.cancel();
    }
  }

  Stream<DBusSignal> _responses(DBusObjectPath path) => DBusSignalStream(
    _client,
    interface: _request,
    name: 'Response',
    path: path,
    signature: DBusSignature('ua{sv}'),
  );

  /// `a(sa{sv})` as the portal answers it, by id; anything malformed is
  /// left out rather than thrown, so one odd entry does not hide the rest.
  static Map<String, PortalShortcut> parseShortcuts(DBusValue? value) {
    if (value is! DBusArray) return const {};
    return {
      for (final entry in value.children)
        if (entry case DBusStruct(children: [DBusString id, DBusDict dict]))
          id.value: _shortcut(dict),
    };
  }

  static PortalShortcut _shortcut(DBusDict dict) {
    String text(String key) => switch (dict.children[DBusString(key)]) {
      DBusVariant(value: DBusString(:final value)) => value,
      _ => '',
    };
    return (
      description: text('description'),
      trigger: text('trigger_description'),
    );
  }
}
