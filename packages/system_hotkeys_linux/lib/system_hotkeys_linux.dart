/// The Linux implementation of `system_hotkeys`, through the
/// `org.freedesktop.portal.GlobalShortcuts` desktop portal.
///
/// Apps use `package:system_hotkeys`; this package registers itself. An app
/// that is not a Snap or Flatpak names its installed `.desktop` file once,
/// before the first shortcut is bound:
///
/// ```dart
/// SystemHotkeysLinux.registerWith(applicationId: 'com.example.app');
/// ```
library;

import 'dart:async';

import 'package:dbus/dbus.dart';
import 'package:flutter/foundation.dart';
import 'package:system_hotkeys_platform_interface/system_hotkeys_platform_interface.dart';

import 'src/global_shortcuts_portal.dart';

export 'src/global_shortcuts_portal.dart' show GlobalShortcutsPortal;

/// System-wide shortcuts on Linux, through the GlobalShortcuts portal: KDE
/// Plasma 5.27 and later, GNOME 48 and later, on Wayland and on X11.
///
/// The desktop decides the keys. The app's combination goes along as a
/// suggestion; the desktop may show the person a dialog first (GNOME does,
/// once per app), binds what it settled on and says so in its own words
/// ([triggers]). The person changes them in the desktop's settings
/// ([configure]). Nothing here sees a key that is not one of the app's
/// shortcuts, and there is no key grab.
///
/// The portal binds a session's shortcuts once, so every change binds the
/// whole set again in a new session; the desktop remembers what the person
/// chose for an id and asks only about new ones.
///
/// Where the portal or a backend for it is missing (wlroots compositors such
/// as Sway and Niri, old desktops) every shortcut is
/// [HotKeyResult.unsupported] and nothing throws.
class SystemHotkeysLinux extends SystemHotkeysPlatform {
  SystemHotkeysLinux({this.applicationId, DBusClient Function()? connect})
    : _connect = connect ?? DBusClient.session;

  /// Installs this implementation; Flutter calls it with no [applicationId]
  /// on start. An app outside a sandbox calls it again with its id before it
  /// binds a shortcut.
  static void registerWith({String? applicationId}) {
    final current = SystemHotkeysPlatform.instance;
    if (current is SystemHotkeysLinux) {
      current.applicationId = applicationId ?? current.applicationId;
    } else {
      SystemHotkeysPlatform.instance = SystemHotkeysLinux(
        applicationId: applicationId,
      );
    }
  }

  /// The id the portal knows this app by: the basename of its installed
  /// `.desktop` file, without the extension. Only for an app outside a
  /// sandbox (an AppImage, a tarball): a Snap or Flatpak is known by its
  /// sandbox and the portal turns the registration down, which is ignored.
  /// Without an installed `.desktop` file GNOME refuses the session and the
  /// shortcuts are [HotKeyResult.unsupported].
  String? applicationId;

  final DBusClient Function() _connect;

  final _wanted = <String, ({HotKey hotKey, String description})>{};
  final _events = StreamController<HotKeyEvent>.broadcast();
  final _triggers = StreamController<Map<String, String>>.broadcast();

  DBusClient? _client;
  GlobalShortcutsPortal? _portal;
  int _version = 0;
  bool _unavailable = false;
  final _subscriptions = <StreamSubscription<Object?>>[];
  String? _session;
  Map<String, String> _bound = const {};

  /// Calls run one after another: two binds at once would race for the
  /// session.
  Future<void> _queue = Future.value();
  Future<T> _serial<T>(Future<T> Function() task) {
    final next = _queue.then((_) => task());
    _queue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  @override
  HotKeyCapabilities get capabilities =>
      const HotKeyCapabilities(configureExternally: true);

  @override
  Future<HotKeyResult> register(
    String id,
    HotKey hotKey, {
    String? description,
  }) async =>
      (await registerAll({id: hotKey}, descriptions: {id: ?description}))[id]!;

  @override
  Future<Map<String, HotKeyResult>> registerAll(
    Map<String, HotKey> hotKeys, {
    Map<String, String> descriptions = const {},
  }) => _serial(() async {
    final refused = <String>{};
    for (final MapEntry(key: id, value: hotKey) in hotKeys.entries) {
      if (!hotKey.hasModifier || preferredTrigger(hotKey) == null) {
        _wanted.remove(id);
        refused.add(id);
      } else {
        _wanted[id] = (
          hotKey: hotKey,
          description: descriptions[id] ?? _wanted[id]?.description ?? id,
        );
      }
    }
    final results = await _bind();
    return {
      for (final id in hotKeys.keys)
        id: refused.contains(id)
            ? HotKeyResult.unsupported
            : results[id] ?? HotKeyResult.unsupported,
    };
  });

  @override
  Future<void> unregister(String id) => _serial(() async {
    if (_wanted.remove(id) != null) await _bind();
  });

  @override
  Future<void> unregisterAll() => _serial(() async {
    _wanted.clear();
    await _bind();
  });

  @override
  Stream<HotKeyEvent> get events => _events.stream;

  @override
  Stream<Map<String, String>> get triggers => _triggers.stream;

  @override
  Future<bool> configure() => _serial(() async {
    final (portal, session) = (_portal, _session);
    if (portal == null || session == null || _version < 2) return false;
    try {
      await portal.configureShortcuts(session);
      return true;
    } on DBusMethodResponseException catch (error) {
      debugPrint('system_hotkeys_linux: no settings opened ($error)');
      return false;
    }
  });

  /// Binds [_wanted] in a fresh session and answers for each id.
  Future<Map<String, HotKeyResult>> _bind() async {
    await _closeSession();
    if (_wanted.isEmpty) return const {};
    final portal = await _open();
    if (portal == null) {
      return {for (final id in _wanted.keys) id: HotKeyResult.unsupported};
    }
    final PortalResponse code;
    final Map<String, PortalShortcut> shortcuts;
    final String session;
    try {
      session = await portal.createSession();
      (code, shortcuts) = await portal.bindShortcuts(session, {
        for (final MapEntry(key: id, value: w) in _wanted.entries)
          id: (
            description: w.description,
            trigger: preferredTrigger(w.hotKey)!,
          ),
      });
    } on Object catch (error) {
      // GNOME refuses a host app it cannot tie to a `.desktop` file ("An app
      // id is required"); other backends fail in their own words.
      debugPrint('system_hotkeys_linux: no session ($error)');
      return {for (final id in _wanted.keys) id: HotKeyResult.unsupported};
    }
    _session = session;
    if (code != PortalResponse.success) {
      await _closeSession();
      final result = code == PortalResponse.cancelled
          ? HotKeyResult.declined
          : HotKeyResult.unsupported;
      return {for (final id in _wanted.keys) id: result};
    }
    _publish({for (final e in shortcuts.entries) e.key: e.value.trigger});
    return {
      for (final id in _wanted.keys)
        id: shortcuts.containsKey(id)
            ? HotKeyResult.bound
            : HotKeyResult.declined,
    };
  }

  /// The portal, once per connection; null where there is none to use.
  Future<GlobalShortcutsPortal?> _open() async {
    if (_portal case final portal?) return portal;
    if (_unavailable) return null;
    final client = _connect();
    final portal = GlobalShortcutsPortal(client);
    // Before anything else: the portal ties the connection to an app on its
    // first call and refuses the registration afterwards.
    if (applicationId case final appId?) {
      try {
        await portal.registerApp(appId);
      } on Object catch (error) {
        debugPrint('system_hotkeys_linux: not registered as $appId ($error)');
      }
    }
    try {
      _version = await portal.version();
    } on Object catch (error) {
      debugPrint('system_hotkeys_linux: no GlobalShortcuts portal ($error)');
      _unavailable = true;
      await client.close();
      return null;
    }
    _client = client;
    _portal = portal;
    _subscriptions.addAll([
      portal.activated.listen((press) {
        final (session, id) = press;
        if (session == _session) _events.add(HotKeyEvent(id));
      }),
      portal.shortcutsChanged.listen((change) {
        final (session, shortcuts) = change;
        if (session != _session) return;
        _publish({
          ..._bound,
          for (final e in shortcuts.entries) e.key: e.value.trigger,
        });
      }),
      client.nameOwnerChanged
          .where((e) => e.name == GlobalShortcutsPortal.busName)
          .listen((_) => unawaited(_serial(_portalRestarted))),
    ]);
    return portal;
  }

  /// The portal went away or came back: its sessions and the registration
  /// went with it. Bind again on a new connection, which registers anew.
  Future<void> _portalRestarted() async {
    await _disconnect();
    if (_wanted.isNotEmpty) await _bind();
  }

  Future<void> _closeSession() async {
    final (portal, session) = (_portal, _session);
    _session = null;
    if (_bound.isNotEmpty) _publish(const {});
    if (portal == null || session == null) return;
    try {
      await portal.closeSession(session);
    } on DBusMethodResponseException {
      // Gone already, with the portal or by the desktop's hand.
    }
  }

  Future<void> _disconnect() async {
    _session = null;
    _unavailable = false;
    _portal = null;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    _subscriptions.clear();
    await _client?.close();
    _client = null;
    if (_bound.isNotEmpty) _publish(const {});
  }

  void _publish(Map<String, String> triggers) {
    _bound = Map.unmodifiable(triggers);
    _triggers.add(_bound);
  }

  /// [hotKey] in the syntax of the XDG shortcuts specification, the
  /// `preferred_trigger` the portal takes: modifiers, then an xkb keysym
  /// name, joined by `+` (`CTRL+ALT+s`, `LOGO+SHIFT+F1`). Null for a key
  /// without a name here, which [registerAll] answers as unsupported.
  @visibleForTesting
  static String? preferredTrigger(HotKey hotKey) {
    const names = {
      HotKeyModifier.control: 'CTRL',
      HotKeyModifier.alt: 'ALT',
      HotKeyModifier.shift: 'SHIFT',
      HotKeyModifier.meta: 'LOGO',
    };
    final usage = hotKey.key.usbHidUsage & 0xffff;
    final key = switch (usage) {
      >= 0x04 && <= 0x1d => String.fromCharCode(0x61 + usage - 0x04),
      >= 0x1e && <= 0x26 => '${usage - 0x1e + 1}',
      0x27 => '0',
      >= 0x3a && <= 0x45 => 'F${usage - 0x3a + 1}',
      0x2c => 'space',
      _ => null,
    };
    if (key == null) return null;
    return [
      for (final m in HotKeyModifier.values)
        if (hotKey.modifiers.contains(m)) names[m]!,
      key,
    ].join('+');
  }
}
