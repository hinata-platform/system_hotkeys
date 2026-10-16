# system_hotkeys_linux

The Linux implementation of [`system_hotkeys`](https://pub.dev/packages/system_hotkeys),
through the `org.freedesktop.portal.GlobalShortcuts` desktop portal. Pure Dart
on [`dbus`](https://pub.dev/packages/dbus): no native code, no key grab, and it
works on Wayland as well as X11.

Apps depend on `system_hotkeys`; this package is endorsed and registers itself.

## How the portal differs

The desktop, not the app, decides the keys. `SystemHotkeys.capabilities.configureExternally`
is true here, and:

- The combination passed to `register` goes along as a suggestion
  (`preferred_trigger`). GNOME and KDE Plasma 6 show a dialog the first time;
  until the person confirms it, KDE keeps the suggestion as the default and
  binds the id without keys (an empty trigger). What the desktop settled on
  arrives through `SystemHotkeys.triggers`, in its own words.
- Bind the whole set with `SystemHotkeys.registerAll`: the portal binds a
  session once, so every change binds the set again in a new session, and the
  desktop asks only about ids it has not seen.
- `HotKeyResult.declined` means the person said no in that dialog;
  `SystemHotkeys.configure()` opens the desktop's shortcut settings (portal
  version 2) so they can change their mind.

| Desktop | Result |
|---|---|
| KDE Plasma 5.27+, GNOME 48+ (Wayland or X11) | bound, triggers reported |
| Sway, Niri and other wlroots compositors, older desktops | `unsupported`, nothing thrown |

## App id outside a sandbox

A Snap or Flatpak is known to the portal by its sandbox. Any other app (an
AppImage, a tarball, `flutter run`) tells the portal which installed `.desktop`
file it is, before the first shortcut:

```dart
import 'package:system_hotkeys_linux/system_hotkeys_linux.dart';

SystemHotkeysLinux.registerWith(applicationId: 'com.example.app');
```

The id is the basename of the `.desktop` file without the extension, and the
file must be installed (`~/.local/share/applications` or
`/usr/share/applications`). Without it GNOME refuses the session and the
shortcuts come back `unsupported`. This needs xdg-desktop-portal 1.20 or later;
older portals ignore it.

## License

MIT
