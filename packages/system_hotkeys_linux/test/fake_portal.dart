import 'dart:async';
import 'dart:io';

import 'package:dbus/dbus.dart';

/// A private session bus with a GlobalShortcuts portal on it that answers
/// the way xdg-desktop-portal does: requests answer through a `Response`
/// signal on the predictable request path, `BindShortcuts` binds what
/// [bindOnly] allows. Everything it was asked lands in [calls].
class FakePortal {
  FakePortal._(this._server, this._dir, this.address, this._client);

  final DBusServer _server;
  final Directory _dir;
  final DBusAddress address;
  final DBusClient _client;
  late final _PortalObject _object;

  /// Method names in the order they arrived, `Registry.Register` included.
  final calls = <String>[];

  /// The shortcuts of every `BindShortcuts`, in order.
  final binds = <Map<String, Map<String, String>>>[];

  final closed = <String>[];
  final configured = <String>[];
  String? registeredAppId;

  int version = 2;
  bool hasRegistry = true;

  /// The answer to the next `BindShortcuts`: 0 success, 1 cancelled.
  int bindResponse = 0;

  /// Ids the "desktop" binds; null binds all.
  Set<String>? bindOnly;

  /// What `CreateSession` fails with, as GNOME does for an unknown host app.
  String? createSessionError;

  /// The trigger the "desktop" reports, by id; defaults to the suggestion.
  final triggers = <String, String>{};

  final _sessions = <String>[];
  String? get session => _sessions.isEmpty ? null : _sessions.last;

  static Future<FakePortal> start({bool withPortal = true}) async {
    final dir = await Directory.systemTemp.createTemp('fake_portal');
    final server = DBusServer();
    final address = await server.listenAddress(
      DBusAddress.unix(path: '${dir.path}/bus'),
    );
    final client = DBusClient(address, authClient: DBusAuthClient(uid: '0'));
    final portal = FakePortal._(server, dir, address, client);
    portal._object = _PortalObject(portal);
    if (withPortal) {
      await client.registerObject(portal._object);
      await client.requestName(
        'org.freedesktop.portal.Desktop',
        flags: {DBusRequestNameFlag.doNotQueue},
      );
    }
    return portal;
  }

  /// A connection for the code under test.
  DBusClient connect() =>
      DBusClient(address, authClient: DBusAuthClient(uid: '0'));

  Future<void> press(String id, {String? session}) => _client.emitSignal(
    path: _PortalObject.portalPath,
    interface: _PortalObject.interface,
    name: 'Activated',
    values: [
      DBusObjectPath(session ?? this.session!),
      DBusString(id),
      const DBusUint64(1),
      DBusDict.stringVariant(const {}),
    ],
  );

  Future<void> change(Map<String, String> triggers) => _client.emitSignal(
    path: _PortalObject.portalPath,
    interface: _PortalObject.interface,
    name: 'ShortcutsChanged',
    values: [
      DBusObjectPath(session!),
      _shortcuts({for (final e in triggers.entries) e.key: ('', e.value)}),
    ],
  );

  /// Drops the portal's name and takes it back, as a restarted portal,
  /// which knows nothing of earlier calls.
  Future<void> restart() async {
    calls.clear();
    await _client.releaseName('org.freedesktop.portal.Desktop');
    await _client.requestName('org.freedesktop.portal.Desktop');
  }

  Future<void> close() async {
    await _client.close();
    await _server.close();
    await _dir.delete(recursive: true);
  }

  Future<void> _respond(
    DBusMethodCall call,
    String token,
    int code,
    Map<String, DBusValue> results,
  ) async {
    final path = _requestPath(call, token);
    // After the reply, as the real portal does.
    scheduleMicrotask(
      () => _client.emitSignal(
        path: path,
        interface: 'org.freedesktop.portal.Request',
        name: 'Response',
        values: [DBusUint32(code), DBusDict.stringVariant(results)],
      ),
    );
  }

  DBusObjectPath _requestPath(DBusMethodCall call, String token) =>
      DBusObjectPath(
        '/org/freedesktop/portal/desktop/request/'
        '${call.sender!.substring(1).replaceAll('.', '_')}/$token',
      );

  static DBusArray _shortcuts(Map<String, (String, String)> shortcuts) =>
      DBusArray(DBusSignature('(sa{sv})'), [
        for (final MapEntry(key: id, value: (description, trigger))
            in shortcuts.entries)
          DBusStruct([
            DBusString(id),
            DBusDict.stringVariant({
              'description': DBusString(description),
              'trigger_description': DBusString(trigger),
            }),
          ]),
      ]);
}

class _PortalObject extends DBusObject {
  _PortalObject(this.fake) : super(portalPath);

  static final portalPath = DBusObjectPath('/org/freedesktop/portal/desktop');
  static const interface = 'org.freedesktop.portal.GlobalShortcuts';

  final FakePortal fake;

  @override
  Future<DBusMethodResponse> getProperty(String iface, String name) async {
    fake.calls.add(name);
    if (iface == interface && name == 'version') {
      return DBusGetPropertyResponse(DBusUint32(fake.version));
    }
    return DBusMethodErrorResponse.unknownProperty();
  }

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    fake.calls.add(call.name);
    if (call.interface == 'org.freedesktop.host.portal.Registry') {
      if (!fake.hasRegistry) return DBusMethodErrorResponse.unknownInterface();
      if (fake.calls.length > 1) {
        return DBusMethodErrorResponse.failed('Registration after a call');
      }
      fake.registeredAppId = call.values[0].asString();
      return DBusMethodSuccessResponse();
    }
    if (call.interface != interface) {
      return DBusMethodErrorResponse.unknownInterface();
    }
    switch (call.name) {
      case 'CreateSession':
        if (fake.createSessionError case final error?) {
          return DBusMethodErrorResponse.failed(error);
        }
        final options = call.values[0].asStringVariantDict();
        final path =
            '/org/freedesktop/portal/desktop/session/'
            '${call.sender!.substring(1).replaceAll('.', '_')}/'
            '${options['session_handle_token']!.asString()}';
        fake._sessions.add(path);
        await fake._client.registerObject(_SessionObject(fake, path));
        await fake._respond(call, options['handle_token']!.asString(), 0, {
          'session_handle': DBusString(path),
        });
        return DBusMethodSuccessResponse([
          fake._requestPath(call, options['handle_token']!.asString()),
        ]);
      case 'BindShortcuts':
        final asked = {
          for (final s in call.values[1].asArray())
            (s as DBusStruct).children[0].asString(): {
              for (final e in s.children[1].asStringVariantDict().entries)
                e.key: e.value.asString(),
            },
        };
        fake.binds.add(asked);
        final options = call.values[3].asStringVariantDict();
        final token = options['handle_token']!.asString();
        await fake._respond(call, token, fake.bindResponse, {
          if (fake.bindResponse == 0)
            'shortcuts': FakePortal._shortcuts({
              for (final MapEntry(key: id, value: s) in asked.entries)
                if (fake.bindOnly?.contains(id) ?? true)
                  id: (
                    s['description'] ?? '',
                    fake.triggers[id] ?? s['preferred_trigger'] ?? '',
                  ),
            }),
        });
        return DBusMethodSuccessResponse([fake._requestPath(call, token)]);
      case 'ConfigureShortcuts':
        fake.configured.add(call.values[0].asObjectPath().value);
        return DBusMethodSuccessResponse();
    }
    return DBusMethodErrorResponse.unknownMethod();
  }
}

class _SessionObject extends DBusObject {
  _SessionObject(this.fake, String path) : super(DBusObjectPath(path));

  final FakePortal fake;

  @override
  Future<DBusMethodResponse> handleMethodCall(DBusMethodCall call) async {
    if (call.name != 'Close') return DBusMethodErrorResponse.unknownMethod();
    fake.closed.add(path.value);
    await fake._client.unregisterObject(this);
    return DBusMethodSuccessResponse();
  }
}
