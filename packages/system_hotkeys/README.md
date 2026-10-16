# system_hotkeys

System-wide keyboard shortcuts for Flutter desktop apps: a combination the
user presses anywhere reaches your app, focused or not.

```dart
import 'package:system_hotkeys/system_hotkeys.dart';

final result = await SystemHotkeys.register(
  'toggle',
  const HotKey(
    key: PhysicalKeyboardKey.keyS,
    modifiers: {HotKeyModifier.control, HotKeyModifier.alt, HotKeyModifier.meta},
  ),
);

switch (result) {
  case HotKeyResult.bound:
    break;
  case HotKeyResult.conflict:
    // Another app or the system holds it. Nothing was bound; tell the user.
    break;
  case HotKeyResult.unsupported:
    // Not on this platform, or a combination without a modifier.
    break;
  case HotKeyResult.declined:
    // Linux: the person said no in the desktop's dialog.
    break;
}

SystemHotkeys.events.listen((event) {
  if (event.id == 'toggle') startOrStop();
});

await SystemHotkeys.unregister('toggle');
```

## How it works

| Platform | API | Conflicts reported |
|---|---|---|
| macOS 10.15+ | `RegisterEventHotKey` | enabled system shortcuts (`CopySymbolicHotKeys`) and combinations this app already holds |
| Windows 10+ | `RegisterHotKey` | any combination another app or the system holds (`ERROR_HOTKEY_ALREADY_REGISTERED`) |
| Linux (KDE Plasma 5.27+, GNOME 48+) | `org.freedesktop.portal.GlobalShortcuts` | the desktop decides the keys, see below |
| others | — | `register` answers `unsupported` |

No platform sees a key outside the bound combinations, so nothing asks for
Accessibility or Input Monitoring, and the plugin works in the macOS App
Sandbox.

**One limit on macOS:** a shortcut another *app* registered cannot be seen from
a sandboxed process, and `RegisterEventHotKey` accepts it. Offer the user a
"press it now" check after binding; it is the only proof that works everywhere.

## Linux

The desktop decides the keys (`SystemHotkeys.capabilities.configureExternally`).
Your combination is a suggestion; the desktop may ask the person first, binds
what it settled on and reports it through `SystemHotkeys.triggers`.
`SystemHotkeys.configure()` opens its shortcut settings. Bind the whole set with
`registerAll`, so the person is asked once. Sway and other wlroots compositors
have no portal backend and answer `unsupported`. An app outside a Snap or
Flatpak names its installed `.desktop` file, see
[`system_hotkeys_linux`](https://pub.dev/packages/system_hotkeys_linux).

## Keys

Letters, digits, F1 to F12 and the space bar, with at least one modifier. Keys
are physical positions (`PhysicalKeyboardKey`), so a combination recorded on a
German layout is the same key on a US one. `HotKey.toMap`/`HotKey.fromMap`
store a combination.

## License

MIT
