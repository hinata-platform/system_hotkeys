import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_hotkeys_linux/system_hotkeys_linux.dart';
import 'package:system_hotkeys_platform_interface/system_hotkeys_platform_interface.dart';

import 'fake_portal.dart';

void main() {
  late FakePortal portal;
  late SystemHotkeysLinux hotkeys;

  const toggle = HotKey(
    key: PhysicalKeyboardKey.keyS,
    modifiers: {
      HotKeyModifier.control,
      HotKeyModifier.alt,
      HotKeyModifier.shift,
    },
  );
  const focus = HotKey(
    key: PhysicalKeyboardKey.keyF,
    modifiers: {HotKeyModifier.control, HotKeyModifier.meta},
  );

  Future<void> setUpPortal({bool withPortal = true}) async {
    portal = await FakePortal.start(withPortal: withPortal);
    hotkeys = SystemHotkeysLinux(
      applicationId: 'com.example.app',
      connect: portal.connect,
    );
  }

  Future<void> tearDownPortal() async {
    await hotkeys.unregisterAll();
    await portal.close();
  }

  group('with a portal', () {
    setUp(setUpPortal);
    tearDown(tearDownPortal);

    test('registers the app before its first portal call', () async {
      await hotkeys.register('toggle', toggle);
      expect(portal.registeredAppId, 'com.example.app');
      expect(portal.calls.first, 'Register');
    });

    test('binds the whole set in one session and reports triggers', () async {
      final triggers = hotkeys.triggers.first;
      final results = await hotkeys.registerAll(
        {'toggle': toggle, 'focus': focus},
        descriptions: {'toggle': 'Start or stop', 'focus': 'Open focus'},
      );
      expect(results, {
        'toggle': HotKeyResult.bound,
        'focus': HotKeyResult.bound,
      });
      expect(portal.binds, hasLength(1));
      expect(portal.binds.single, {
        'toggle': {
          'description': 'Start or stop',
          'preferred_trigger': 'CTRL+ALT+SHIFT+s',
        },
        'focus': {
          'description': 'Open focus',
          'preferred_trigger': 'CTRL+LOGO+f',
        },
      });
      expect(await triggers, {
        'toggle': 'CTRL+ALT+SHIFT+s',
        'focus': 'CTRL+LOGO+f',
      });
    });

    test('an id the desktop left out is declined', () async {
      portal.bindOnly = {'focus'};
      expect(await hotkeys.registerAll({'toggle': toggle, 'focus': focus}), {
        'toggle': HotKeyResult.declined,
        'focus': HotKeyResult.bound,
      });
    });

    test('a cancelled dialog declines all and ends the session', () async {
      portal.bindResponse = 1;
      expect(await hotkeys.register('toggle', toggle), HotKeyResult.declined);
      expect(portal.closed, [portal.session]);
      expect(await hotkeys.configure(), isFalse);
    });

    test('presses of the current session arrive by id', () async {
      await hotkeys.register('toggle', toggle);
      final press = hotkeys.events.first;
      await portal.press('toggle', session: '/stale/session');
      await portal.press('toggle');
      expect(await press, const HotKeyEvent('toggle'));
    });

    test('a changed trigger is reported with the others', () async {
      portal.triggers['focus'] = 'Ctrl+Super+F';
      await hotkeys.registerAll({'toggle': toggle, 'focus': focus});
      final changed = hotkeys.triggers.first;
      await portal.change({'toggle': 'Alt+T'});
      expect(await changed, {'toggle': 'Alt+T', 'focus': 'Ctrl+Super+F'});
    });

    test('a change binds the rest again in a new session', () async {
      await hotkeys.registerAll({'toggle': toggle, 'focus': focus});
      final first = portal.session;
      await hotkeys.unregister('focus');
      expect(portal.closed, [first]);
      expect(portal.binds.last.keys, ['toggle']);
      await hotkeys.unregisterAll();
      expect(portal.closed, hasLength(2));
      expect(portal.binds, hasLength(2));
    });

    test('a combination without a modifier never reaches the portal', () async {
      const bare = HotKey(key: PhysicalKeyboardKey.keyS, modifiers: {});
      expect(await hotkeys.register('toggle', bare), HotKeyResult.unsupported);
      expect(portal.binds, isEmpty);
    });

    test('configure opens the desktop settings from version 2 on', () async {
      await hotkeys.register('toggle', toggle);
      expect(await hotkeys.configure(), isTrue);
      expect(portal.configured, [portal.session]);
    });

    test('version 1 has no settings to open', () async {
      portal.version = 1;
      await hotkeys.register('toggle', toggle);
      expect(await hotkeys.configure(), isFalse);
    });

    test(
      'a host app GNOME cannot place is unsupported, not an error',
      () async {
        portal.createSessionError = 'An app id is required';
        expect(
          await hotkeys.register('toggle', toggle),
          HotKeyResult.unsupported,
        );
      },
    );

    test('a portal without the registry still binds', () async {
      portal.hasRegistry = false;
      expect(await hotkeys.register('toggle', toggle), HotKeyResult.bound);
    });

    test('a restarted portal gets the shortcuts bound again', () async {
      await hotkeys.register('toggle', toggle);
      final rebound = hotkeys.triggers.firstWhere((t) => t.isNotEmpty);
      await portal.restart();
      expect(await rebound, {'toggle': 'CTRL+ALT+SHIFT+s'});
      expect(portal.binds, hasLength(2));
    });
  });

  test('without a portal every shortcut is unsupported', () async {
    await setUpPortal(withPortal: false);
    addTearDown(tearDownPortal);
    expect(await hotkeys.registerAll({'toggle': toggle, 'focus': focus}), {
      'toggle': HotKeyResult.unsupported,
      'focus': HotKeyResult.unsupported,
    });
    expect(await hotkeys.configure(), isFalse);
  });

  test('suggests triggers in the XDG shortcuts syntax', () {
    String trigger(PhysicalKeyboardKey key, Set<HotKeyModifier> modifiers) =>
        SystemHotkeysLinux.preferredTrigger(
          HotKey(key: key, modifiers: modifiers),
        );
    expect(
      trigger(PhysicalKeyboardKey.keyA, {HotKeyModifier.control}),
      'CTRL+a',
    );
    expect(
      trigger(PhysicalKeyboardKey.digit1, {HotKeyModifier.meta}),
      'LOGO+1',
    );
    expect(trigger(PhysicalKeyboardKey.digit0, {HotKeyModifier.alt}), 'ALT+0');
    expect(
      trigger(PhysicalKeyboardKey.f12, {
        HotKeyModifier.shift,
        HotKeyModifier.control,
      }),
      'CTRL+SHIFT+F12',
    );
    expect(
      trigger(PhysicalKeyboardKey.space, {HotKeyModifier.control}),
      'CTRL+space',
    );
  });

  test('says the desktop configures the keys', () {
    expect(SystemHotkeysLinux().capabilities.configureExternally, isTrue);
  });
}
