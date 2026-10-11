## 0.1.2

* The method and event channels belong to the plugin and go with it.
* Hot key numbers freed by `unregister` are used again instead of counting up to Windows' limit.
* Modifier bits outside the four modifiers, or none of them, are refused natively too.

## 0.1.0

* First release: register, unregister and press events through RegisterHotKey.
