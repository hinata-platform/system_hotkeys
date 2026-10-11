## 0.1.1

* Presses reach the app when another component claims hot-key events on the event dispatcher target before the application target sees them. super_native_extensions (super_clipboard, super_drag_and_drop) does that, so an app using it never got a press. The handler now sits on the dispatcher target itself, is installed again on top on every `register` and whenever the app goes to the background, and passes hot keys that are not its own on.

## 0.1.0

* First release: register, unregister and press events through RegisterEventHotKey.
