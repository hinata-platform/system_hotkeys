import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'hot_key.dart';
import 'method_channel_system_hotkeys.dart';

/// What a platform implementation of system_hotkeys provides.
///
/// Registration only: the platform's own API for system-wide shortcuts, never
/// an event tap or a keyboard hook that sees every key. Nothing here needs, or
/// asks for, an accessibility permission.
abstract class SystemHotkeysPlatform extends PlatformInterface {
  SystemHotkeysPlatform() : super(token: _token);

  static final Object _token = Object();

  static SystemHotkeysPlatform _instance = MethodChannelSystemHotkeys();

  /// The implementation in use. Defaults to the method channel, which the
  /// macOS and Windows packages answer.
  static SystemHotkeysPlatform get instance => _instance;

  static set instance(SystemHotkeysPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Binds [hotKey] under [id]. Binding an [id] again replaces its old
  /// combination; the old one is released even when the new one fails.
  Future<HotKeyResult> register(String id, HotKey hotKey);

  /// Releases [id]. Unknown ids are ignored.
  Future<void> unregister(String id);

  /// Releases every combination this app bound.
  Future<void> unregisterAll();

  /// Presses of bound combinations.
  Stream<HotKeyEvent> get events;
}
