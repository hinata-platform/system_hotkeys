import Carbon.HIToolbox
import Cocoa
import FlutterMacOS

/// System-wide shortcuts through Carbon's `RegisterEventHotKey`.
///
/// The one API on macOS that delivers a key combination to an app that is not
/// in front without seeing any other key: no event tap, no keyboard monitor, so
/// no Accessibility or Input Monitoring permission, and it works in the App
/// Sandbox. Its `OSStatus` is handed back as is — a combination another app
/// holds comes back as a conflict, never as silence.
public class SystemHotkeysMacosPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  /// "HSHK", so the handler can tell our hot keys from anyone else's in the
  /// same process.
  private static let signature: OSType = 0x4853_484B

  private var refs: [String: EventHotKeyRef] = [:]
  private var numbers: [String: UInt32] = [:]
  private var ids: [UInt32: String] = [:]
  private var nextNumber: UInt32 = 1
  private var handler: EventHandlerRef?
  private var sink: FlutterEventSink?
  private var resignObserver: NSObjectProtocol?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = SystemHotkeysMacosPlugin()
    let methods = FlutterMethodChannel(
      name: "system_hotkeys", binaryMessenger: registrar.messenger)
    registrar.addMethodCallDelegate(instance, channel: methods)
    let events = FlutterEventChannel(
      name: "system_hotkeys/events", binaryMessenger: registrar.messenger)
    events.setStreamHandler(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    switch call.method {
    case "register":
      guard let id = args?["id"] as? String,
        let usage = args?["usage"] as? Int,
        let bits = args?["modifiers"] as? Int
      else {
        result(FlutterError(code: "bad_args", message: "id, usage and modifiers", details: nil))
        return
      }
      result(register(id: id, usage: usage, bits: bits))
    case "unregister":
      if let id = args?["id"] as? String { unregister(id: id) }
      result(nil)
    case "unregisterAll":
      for id in Array(refs.keys) { unregister(id: id) }
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func register(id: String, usage: Int, bits: Int) -> String {
    unregister(id: id)
    guard bits != 0, let keyCode = Self.keyCodes[usage] else { return "unsupported" }
    let modifiers = Self.carbonModifiers(bits)
    // RegisterEventHotKey only refuses a combination this process already
    // holds; one the system reserves (Spotlight, screenshots, Mission Control)
    // it accepts and never delivers. Those are checked here. Another app's
    // shortcut cannot be seen from a sandbox at all — that is what an app's
    // "press it now" self-test is for.
    if Self.systemReserves(keyCode: keyCode, modifiers: modifiers) { return "conflict" }
    guard installHandler(again: true) else { return "unsupported" }

    let number = nextNumber
    nextNumber += 1
    var ref: EventHotKeyRef?
    let status = RegisterEventHotKey(
      keyCode, modifiers, EventHotKeyID(signature: Self.signature, id: number),
      GetApplicationEventTarget(), 0, &ref)
    switch status {
    case noErr:
      guard let ref else { return "unsupported" }
      refs[id] = ref
      numbers[id] = number
      ids[number] = id
      return "bound"
    case OSStatus(eventHotKeyExistsErr):
      return "conflict"
    default:
      return "unsupported"
    }
  }

  private func unregister(id: String) {
    if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    if let number = numbers.removeValue(forKey: id) { ids.removeValue(forKey: number) }
  }

  /// One handler for every hot key, on the event *dispatcher* target.
  ///
  /// Not the application target: another component may sit on the dispatcher
  /// and claim every hot-key event, ours included, before the application
  /// target ever sees it — super_native_extensions does exactly that, and an
  /// app using its clipboard or drag and drop then never received a press.
  /// Carbon calls the handlers of a target newest first, so this one is
  /// installed again whenever it might have been buried: on each `register`,
  /// and whenever the app goes to the background, which is the moment before
  /// someone presses a shortcut in another app. Hot keys that are not ours are
  /// passed on with `eventNotHandledErr`.
  private func installHandler(again: Bool = false) -> Bool {
    if handler != nil && !again { return true }
    if let old = handler {
      RemoveEventHandler(old)
      handler = nil
    }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    let me = Unmanaged.passUnretained(self).toOpaque()
    let status = InstallEventHandler(
      GetEventDispatcherTarget(),
      { _, event, context in
        guard let event, let context else { return OSStatus(eventNotHandledErr) }
        var hotKey = EventHotKeyID()
        let read = GetEventParameter(
          event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
          nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKey)
        let plugin = Unmanaged<SystemHotkeysMacosPlugin>.fromOpaque(context)
          .takeUnretainedValue()
        guard read == noErr, hotKey.signature == SystemHotkeysMacosPlugin.signature,
          let id = plugin.ids[hotKey.id]
        else { return OSStatus(eventNotHandledErr) }
        plugin.sink?(id)
        return noErr
      }, 1, &spec, me, &handler)
    if status == noErr && resignObserver == nil {
      resignObserver = NotificationCenter.default.addObserver(
        forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self, !self.refs.isEmpty else { return }
        _ = self.installHandler(again: true)
      }
    }
    return status == noErr
  }

  deinit {
    for ref in refs.values { UnregisterEventHotKey(ref) }
    if let handler { RemoveEventHandler(handler) }
    if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    sink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  /// Whether an enabled system shortcut (System Settings → Keyboard →
  /// Keyboard Shortcuts) uses this combination.
  private static func systemReserves(keyCode: UInt32, modifiers: UInt32) -> Bool {
    var unmanaged: Unmanaged<CFArray>?
    guard CopySymbolicHotKeys(&unmanaged) == noErr,
      let hotKeys = unmanaged?.takeRetainedValue() as? [[String: Any]]
    else { return false }
    let relevant = UInt32(controlKey | optionKey | shiftKey | cmdKey)
    return hotKeys.contains { entry in
      guard (entry[kHISymbolicHotKeyEnabled as String] as? Bool) == true,
        let code = (entry[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value,
        let mods = (entry[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value
      else { return false }
      return code == keyCode && (mods & relevant) == modifiers
    }
  }

  /// The bit order of `HotKeyModifier`: control, alt, shift, meta.
  private static func carbonModifiers(_ bits: Int) -> UInt32 {
    var mods: UInt32 = 0
    if bits & 1 != 0 { mods |= UInt32(controlKey) }
    if bits & 2 != 0 { mods |= UInt32(optionKey) }
    if bits & 4 != 0 { mods |= UInt32(shiftKey) }
    if bits & 8 != 0 { mods |= UInt32(cmdKey) }
    return mods
  }

  /// USB HID usage (keyboard page) to the ANSI virtual key code: the keys of
  /// `HotKey.isSupportedKey`, which are positions, not characters.
  private static let keyCodes: [Int: UInt32] = {
    let letters: [Int] = [
      kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
      kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
      kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
      kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z,
    ]
    let digits: [Int] = [
      kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7,
      kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0,
    ]
    let functions: [Int] = [
      kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
      kVK_F11, kVK_F12,
    ]
    var table: [Int: UInt32] = [0x0007_002C: UInt32(kVK_Space)]
    for (i, code) in letters.enumerated() { table[0x0007_0004 + i] = UInt32(code) }
    for (i, code) in digits.enumerated() { table[0x0007_001E + i] = UInt32(code) }
    for (i, code) in functions.enumerated() { table[0x0007_003A + i] = UInt32(code) }
    return table
  }()
}
