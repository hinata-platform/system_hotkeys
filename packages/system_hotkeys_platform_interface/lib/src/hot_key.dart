import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A modifier key held together with the [HotKey.key].
///
/// [meta] is Command on macOS and the Windows key on Windows.
enum HotKeyModifier { control, alt, shift, meta }

/// A key combination the operating system watches for while the app runs,
/// focused or not.
///
/// The key is a [PhysicalKeyboardKey], the position on the keyboard, because
/// that is what the registration APIs take: a combination recorded on a German
/// layout means the same key on a US one. Only keys that every supported
/// platform can register are accepted, see [isSupportedKey].
@immutable
class HotKey {
  const HotKey({required this.key, required this.modifiers});

  final PhysicalKeyboardKey key;
  final Set<HotKeyModifier> modifiers;

  /// A combination with no modifier would swallow the bare key in every app on
  /// the system. Every platform refuses it here, before it reaches one.
  bool get hasModifier => modifiers.isNotEmpty;

  /// Letters, digits, F1 to F12 and the space bar: the keys the macOS and
  /// Windows tables both carry.
  static bool isSupportedKey(PhysicalKeyboardKey key) =>
      supportedUsages.contains(key.usbHidUsage);

  /// The USB HID usages of [isSupportedKey], in the keyboard page (0x07).
  static final Set<int> supportedUsages = {
    for (var u = 0x00070004; u <= 0x0007001d; u++) u, // A to Z
    for (var u = 0x0007001e; u <= 0x00070027; u++) u, // 1 to 9, 0
    for (var u = 0x0007003a; u <= 0x00070045; u++) u, // F1 to F12
    0x0007002c, // space
  };

  /// What travels over the platform channel: the HID usage and a bit set.
  Map<String, Object> toMap() => {
    'usage': key.usbHidUsage,
    'modifiers': modifiers.fold<int>(0, (bits, m) => bits | (1 << m.index)),
  };

  /// The combination as a stored value, for apps that keep one per user.
  factory HotKey.fromMap(Map<Object?, Object?> map) {
    final bits = map['modifiers']! as int;
    return HotKey(
      key: PhysicalKeyboardKey(map['usage']! as int),
      modifiers: {
        for (final m in HotKeyModifier.values)
          if (bits & (1 << m.index) != 0) m,
      },
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HotKey &&
      other.key == key &&
      setEquals(other.modifiers, modifiers);

  @override
  int get hashCode => Object.hash(key, Object.hashAllUnordered(modifiers));

  @override
  String toString() =>
      'HotKey(${modifiers.map((m) => m.name).join('+')}'
      '${modifiers.isEmpty ? '' : '+'}${key.debugName ?? key.usbHidUsage})';
}

/// What became of a [HotKey] the app asked for.
enum HotKeyResult {
  /// The system delivers it to this app from now on.
  bound,

  /// Another app, or the system, holds the combination. Nothing was bound.
  conflict,

  /// This platform cannot register it: no implementation, a key outside
  /// [HotKey.isSupportedKey], or a combination without a modifier.
  unsupported,
}

/// A registered [HotKey] was pressed. [id] is the one it was registered under.
@immutable
class HotKeyEvent {
  const HotKeyEvent(this.id);

  final String id;

  @override
  bool operator ==(Object other) => other is HotKeyEvent && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'HotKeyEvent($id)';
}
