## 0.1.2

* Modifier bits outside the four modifiers, or none of them, are refused natively too, so a caller that skips the Dart checks cannot bind a bare key in every app.
* The class comment says what macOS reports: enabled system shortcuts and combinations this app already holds, not another app's.

## 0.1.1

* Presses reach the app when another component claims hot-key events on the event dispatcher target before the application target sees them. super_native_extensions (super_clipboard, super_drag_and_drop) does that, so an app using it never got a press. The handler now sits on the dispatcher target itself, is installed again on top on every `register` and whenever the app goes to the background, and passes hot keys that are not its own on.

## 0.1.0

* First release: register, unregister and press events through RegisterEventHotKey.
