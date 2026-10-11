import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_hotkeys_platform_interface/system_hotkeys_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final platform = MethodChannelSystemHotkeys();
  final calls = <MethodCall>[];
  String? answer;

  setUp(() {
    calls.clear();
    answer = 'bound';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MethodChannelSystemHotkeys.methodChannel, (
          call,
        ) async {
          calls.add(call);
          return call.method == 'register' ? answer : null;
        });
  });

  const ctrlAltS = HotKey(
    key: PhysicalKeyboardKey.keyS,
    modifiers: {HotKeyModifier.control, HotKeyModifier.alt},
  );

  test('sends the HID usage and the modifier bits', () async {
    expect(await platform.register('toggle', ctrlAltS), HotKeyResult.bound);
    expect(calls.single.method, 'register');
    expect(calls.single.arguments, {
      'id': 'toggle',
      'usage': PhysicalKeyboardKey.keyS.usbHidUsage,
      'modifiers': 0x3,
    });
  });

  test('reports a conflict instead of swallowing it', () async {
    answer = 'conflict';
    expect(await platform.register('toggle', ctrlAltS), HotKeyResult.conflict);
  });

  test(
    'refuses a combination without a modifier and releases the id',
    () async {
      final result = await platform.register(
        'toggle',
        const HotKey(key: PhysicalKeyboardKey.keyS, modifiers: {}),
      );
      expect(result, HotKeyResult.unsupported);
      expect(calls.map((c) => c.method), ['unregister']);
    },
  );

  test('refuses a key outside the shared table', () async {
    final result = await platform.register(
      'toggle',
      const HotKey(
        key: PhysicalKeyboardKey.capsLock,
        modifiers: {HotKeyModifier.control},
      ),
    );
    expect(result, HotKeyResult.unsupported);
  });

  test('a platform without an implementation answers unsupported', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          MethodChannelSystemHotkeys.methodChannel,
          null,
        );
    expect(
      await platform.register('toggle', ctrlAltS),
      HotKeyResult.unsupported,
    );
    await platform.unregister('toggle');
    await platform.unregisterAll();
  });

  test('a combination survives the round trip through a map', () {
    const combo = HotKey(
      key: PhysicalKeyboardKey.f5,
      modifiers: {HotKeyModifier.meta, HotKeyModifier.shift},
    );
    expect(HotKey.fromMap(combo.toMap()), combo);
  });
}
