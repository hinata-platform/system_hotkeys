## 0.2.1

* Only the portal's own `Response` counts: another client on the session bus can no longer answer a request first.
* A key without an XDG name is answered `unsupported` instead of throwing, whatever the platform interface lists.

## 0.2.0

* First release: system-wide shortcuts through the `org.freedesktop.portal.GlobalShortcuts` portal, pure Dart on D-Bus. The desktop decides the keys and reports them through `triggers`; `configure` opens its settings (portal version 2). Host apps register their app id through `org.freedesktop.host.portal.Registry`. Desktops without a backend answer `unsupported`.
