/// System-wide keyboard shortcuts through the operating system's own
/// registration APIs: `RegisterEventHotKey` on macOS, `RegisterHotKey` on
/// Windows.
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
/// Neither platform sees any key but the bound combinations, so nothing needs
/// or asks for an Accessibility or Input Monitoring permission. Other
/// platforms answer [HotKeyResult.unsupported].
library;

import 'package:system_hotkeys_platform_interface/system_hotkeys_platform_interface.dart';

export 'package:flutter/services.dart' show PhysicalKeyboardKey;
export 'package:system_hotkeys_platform_interface/system_hotkeys_platform_interface.dart'
    show HotKey, HotKeyEvent, HotKeyModifier, HotKeyResult;

/// The system-wide shortcuts of this app.
abstract final class SystemHotkeys {
  static SystemHotkeysPlatform get _platform => SystemHotkeysPlatform.instance;

  /// Binds [hotKey] under [id]. Binding an [id] again replaces its old
  /// combination, which is released even when the new one fails.
  ///
  /// [HotKeyResult.conflict] means another app or the system holds the
  /// combination; [HotKeyResult.unsupported] that this platform cannot bind
  /// it, a combination without a modifier included.
  static Future<HotKeyResult> register(String id, HotKey hotKey) =>
      _platform.register(id, hotKey);

  /// Releases [id]. Unknown ids are ignored.
  static Future<void> unregister(String id) => _platform.unregister(id);

  /// Releases every combination this app bound.
  static Future<void> unregisterAll() => _platform.unregisterAll();

  /// Presses of bound combinations, by the id they were bound under.
  static Stream<HotKeyEvent> get events => _platform.events;
}
