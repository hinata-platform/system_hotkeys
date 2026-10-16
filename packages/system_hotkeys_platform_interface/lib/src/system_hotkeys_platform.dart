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

  /// What this platform does with a combination; see [HotKeyCapabilities].
  HotKeyCapabilities get capabilities => const HotKeyCapabilities();

  /// Binds [hotKey] under [id]. Binding an [id] again replaces its old
  /// combination; the old one is released even when the new one fails.
  ///
  /// [description] says what the shortcut does, for platforms whose system
  /// lists it ([HotKeyCapabilities.configureExternally]).
  Future<HotKeyResult> register(
    String id,
    HotKey hotKey, {
    String? description,
  });

  /// Binds every entry of [hotKeys] as [register] would; ids not named keep
  /// what they have. A platform whose system asks the person
  /// ([HotKeyCapabilities.configureExternally]) asks once for the whole set
  /// instead of once per shortcut. [descriptions] are by id.
  Future<Map<String, HotKeyResult>> registerAll(
    Map<String, HotKey> hotKeys, {
    Map<String, String> descriptions = const {},
  }) async => {
    for (final MapEntry(:key, :value) in hotKeys.entries)
      key: await register(key, value, description: descriptions[key]),
  };

  /// Releases [id]. Unknown ids are ignored.
  Future<void> unregister(String id);

  /// Releases every combination this app bound.
  Future<void> unregisterAll();

  /// Presses of bound combinations.
  Stream<HotKeyEvent> get events;

  /// What the system says triggers each bound id, in its own words ("Ctrl+
  /// Alt+S"), whenever that changes; empty text for an id it bound without
  /// keys. Only where [HotKeyCapabilities.configureExternally]; elsewhere the
  /// app's own combination is the trigger and nothing arrives here.
  Stream<Map<String, String>> get triggers => const Stream.empty();

  /// Opens the system's settings for this app's shortcuts. False where there
  /// are none to open, or the system is too old to offer them.
  Future<bool> configure() async => false;
}
