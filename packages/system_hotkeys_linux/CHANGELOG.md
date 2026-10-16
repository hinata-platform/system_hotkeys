## 0.2.0

* First release: system-wide shortcuts through the `org.freedesktop.portal.GlobalShortcuts` portal, pure Dart on D-Bus. The desktop decides the keys and reports them through `triggers`; `configure` opens its settings (portal version 2). Host apps register their app id through `org.freedesktop.host.portal.Registry`. Desktops without a backend answer `unsupported`.
