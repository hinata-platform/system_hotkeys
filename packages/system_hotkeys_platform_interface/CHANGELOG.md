## 0.2.0

* `HotKeyCapabilities`: `configureExternally` says the desktop, not the app, decides the keys (Linux).
* `registerAll` binds a set at once, so a system that asks the person asks once; `register` takes a `description`.
* `triggers` reports what the system bound in its own words; `configure` opens the system's settings.
* `HotKeyResult.declined`: the person said no in the system's dialog. Breaking for exhaustive switches.

## 0.1.0

* First release: `HotKey`, `HotKeyResult`, `HotKeyEvent` and the method channel implementation.
