## 0.2.0

* Linux, through the `org.freedesktop.portal.GlobalShortcuts` portal (`system_hotkeys_linux`), on Wayland and X11.
* `capabilities`, `registerAll`, `triggers`, `configure` and `HotKeyResult.declined`; see the platform interface.

## 0.1.0

* First release: `register`, `unregister`, `unregisterAll` and `events` on macOS (RegisterEventHotKey) and Windows (RegisterHotKey). Conflicts come back as `HotKeyResult.conflict`.
