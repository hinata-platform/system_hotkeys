/// System-wide keyboard shortcuts through the operating system's own
/// registration APIs: `RegisterEventHotKey` on macOS, `RegisterHotKey` on
/// Windows, the `org.freedesktop.portal.GlobalShortcuts` portal on Linux.
///
/// ```dart
/// final result = await SystemHotkeys.register(
///   'toggle',
///   const HotKey(
///     key: PhysicalKeyboardKey.keyS,
///     modifiers: {HotKeyModifier.control, HotKeyModifier.alt, HotKeyModifier.meta},
///   ),
/// );
/// if (result == HotKeyResult.conflict) {
///   // Another app holds it. Tell the user; nothing was bound.
/// }
/// SystemHotkeys.events.listen((event) => print(event.id));
/// ```
///
/// No platform sees any key but the bound combinations, so nothing needs or
/// asks for an Accessibility or Input Monitoring permission. Other platforms
/// answer [HotKeyResult.unsupported].
///
/// On Linux the desktop decides the keys ([HotKeyCapabilities.
/// configureExternally]): the combination is a suggestion, the desktop may ask
/// the person first, and [SystemHotkeys.triggers] says what it settled on.
library;

import 'package:system_hotkeys_platform_interface/system_hotkeys_platform_interface.dart';

export 'package:flutter/services.dart' show PhysicalKeyboardKey;
export 'package:system_hotkeys_platform_interface/system_hotkeys_platform_interface.dart'
    show HotKey, HotKeyCapabilities, HotKeyEvent, HotKeyModifier, HotKeyResult;

/// The system-wide shortcuts of this app.
abstract final class SystemHotkeys {
  static SystemHotkeysPlatform get _platform => SystemHotkeysPlatform.instance;

  /// What this platform does with a combination.
  static HotKeyCapabilities get capabilities => _platform.capabilities;

  /// Binds [hotKey] under [id]. Binding an [id] again replaces its old
  /// combination, which is released even when the new one fails.
  ///
  /// [HotKeyResult.conflict] means another app or the system holds the
  /// combination; [HotKeyResult.unsupported] that this platform cannot bind
  /// it, a combination without a modifier included; [HotKeyResult.declined]
  /// that the person said no in the system's dialog. [description] is what
  /// the system lists for it, where it lists shortcuts.
  static Future<HotKeyResult> register(
    String id,
    HotKey hotKey, {
    String? description,
  }) => _platform.register(id, hotKey, description: description);

  /// Binds several at once; ids not named keep what they have. Where the
  /// system asks the person, it asks once for the whole set.
  static Future<Map<String, HotKeyResult>> registerAll(
    Map<String, HotKey> hotKeys, {
    Map<String, String> descriptions = const {},
  }) => _platform.registerAll(hotKeys, descriptions: descriptions);

  /// Releases [id]. Unknown ids are ignored.
  static Future<void> unregister(String id) => _platform.unregister(id);

  /// Releases every combination this app bound.
  static Future<void> unregisterAll() => _platform.unregisterAll();

  /// Presses of bound combinations, by the id they were bound under.
  static Stream<HotKeyEvent> get events => _platform.events;

  /// What the system says triggers each bound id, in its own words, whenever
  /// that changes. Only where [HotKeyCapabilities.configureExternally].
  static Stream<Map<String, String>> get triggers => _platform.triggers;

  /// Opens the system's settings for this app's shortcuts; false where there
  /// are none.
  static Future<bool> configure() => _platform.configure();
}
