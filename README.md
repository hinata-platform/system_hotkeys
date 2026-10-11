# system_hotkeys

System-wide keyboard shortcuts for Flutter desktop apps, through the operating
system's own registration APIs.

| Package | |
|---|---|
| [`system_hotkeys`](packages/system_hotkeys) | What apps depend on |
| [`system_hotkeys_platform_interface`](packages/system_hotkeys_platform_interface) | The interface the platforms implement |
| [`system_hotkeys_macos`](packages/system_hotkeys_macos) | `RegisterEventHotKey` (Carbon) |
| [`system_hotkeys_windows`](packages/system_hotkeys_windows) | `RegisterHotKey` |

Linux is planned through the XDG GlobalShortcuts portal.

## Why another hotkey plugin

- **Registration, not a keyboard hook.** The app sees the combinations it bound
  and nothing else: no event tap, no low-level hook, no keylogging, and no
  Accessibility or Input Monitoring permission. It works in the macOS App
  Sandbox.
- **Conflicts are reported, not swallowed.** `register` answers `bound`,
  `conflict` or `unsupported`.
- **No recorder in the plugin.** Recording a combination is your app's UI; the
  plugin takes a `HotKey` value.

See [`packages/system_hotkeys`](packages/system_hotkeys) for usage.

## License

MIT
