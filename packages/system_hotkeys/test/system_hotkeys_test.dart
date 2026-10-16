import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:system_hotkeys/system_hotkeys.dart';
import 'package:system_hotkeys_platform_interface/system_hotkeys_platform_interface.dart';

class _FakePlatform extends SystemHotkeysPlatform
    with MockPlatformInterfaceMixin {
  final bound = <String, HotKey>{};
  final presses = StreamController<HotKeyEvent>.broadcast();
  HotKeyResult next = HotKeyResult.bound;

  @override
  Future<HotKeyResult> register(
    String id,
    HotKey hotKey, {
    String? description,
  }) async {
    bound.remove(id);
    if (next == HotKeyResult.bound) bound[id] = hotKey;
    return next;
  }

  @override
  Future<void> unregister(String id) async => bound.remove(id);

  @override
  Future<void> unregisterAll() async => bound.clear();

  @override
  Stream<HotKeyEvent> get events => presses.stream;
}

void main() {
  late _FakePlatform platform;
  setUp(() => SystemHotkeysPlatform.instance = platform = _FakePlatform());

  const combo = HotKey(
    key: PhysicalKeyboardKey.keyF,
    modifiers: {HotKeyModifier.control, HotKeyModifier.shift},
  );

  test('forwards to the platform', () async {
    expect(await SystemHotkeys.register('focus', combo), HotKeyResult.bound);
    expect(platform.bound, {'focus': combo});
    await SystemHotkeys.unregister('focus');
    expect(platform.bound, isEmpty);
  });

  test('passes a conflict on as it is', () async {
    platform.next = HotKeyResult.conflict;
    expect(await SystemHotkeys.register('focus', combo), HotKeyResult.conflict);
  });

  test('passes presses through by id', () async {
    final first = SystemHotkeys.events.first;
    platform.presses.add(const HotKeyEvent('focus'));
    expect(await first, const HotKeyEvent('focus'));
  });

  test('binds a set one by one where the system does not ask', () async {
    const other = HotKey(
      key: PhysicalKeyboardKey.keyS,
      modifiers: {HotKeyModifier.control, HotKeyModifier.alt},
    );
    expect(await SystemHotkeys.registerAll({'focus': combo, 'toggle': other}), {
      'focus': HotKeyResult.bound,
      'toggle': HotKeyResult.bound,
    });
    expect(platform.bound, {'focus': combo, 'toggle': other});
  });

  test('platforms bind themselves unless they say otherwise', () async {
    expect(SystemHotkeys.capabilities.configureExternally, isFalse);
    expect(await SystemHotkeys.configure(), isFalse);
    expect(await SystemHotkeys.triggers.isEmpty, isTrue);
  });
}
