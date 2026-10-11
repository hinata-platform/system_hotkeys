#include "system_hotkeys_windows_plugin.h"

#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <vector>

namespace system_hotkeys_windows {

namespace {

// The bit order of HotKeyModifier: control, alt, shift, meta.
UINT WindowsModifiers(int64_t bits) {
  UINT mods = MOD_NOREPEAT;
  if (bits & 1) mods |= MOD_CONTROL;
  if (bits & 2) mods |= MOD_ALT;
  if (bits & 4) mods |= MOD_SHIFT;
  if (bits & 8) mods |= MOD_WIN;
  return mods;
}

// USB HID usage (keyboard page) to the virtual key: the keys of
// HotKey.isSupportedKey. 0 for anything else.
UINT VirtualKey(int64_t usage) {
  if (usage >= 0x00070004 && usage <= 0x0007001d) {
    return 'A' + static_cast<UINT>(usage - 0x00070004);
  }
  if (usage >= 0x0007001e && usage <= 0x00070026) {
    return '1' + static_cast<UINT>(usage - 0x0007001e);
  }
  if (usage == 0x00070027) return '0';
  if (usage >= 0x0007003a && usage <= 0x00070045) {
    return VK_F1 + static_cast<UINT>(usage - 0x0007003a);
  }
  if (usage == 0x0007002c) return VK_SPACE;
  return 0;
}

template <typename T>
const T* Arg(const flutter::EncodableMap& args, const char* key) {
  auto it = args.find(flutter::EncodableValue(key));
  return it == args.end() ? nullptr : std::get_if<T>(&it->second);
}

int64_t Number(const flutter::EncodableMap& args, const char* key) {
  if (auto value = Arg<int32_t>(args, key)) return *value;
  if (auto value = Arg<int64_t>(args, key)) return *value;
  return -1;
}

}  // namespace

void SystemHotkeysWindowsPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto plugin = std::make_unique<SystemHotkeysWindowsPlugin>(registrar);
  auto* raw = plugin.get();

  auto methods =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          registrar->messenger(), "system_hotkeys",
          &flutter::StandardMethodCodec::GetInstance());
  methods->SetMethodCallHandler([raw](const auto& call, auto result) {
    raw->HandleMethodCall(call, std::move(result));
  });

  auto events =
      std::make_unique<flutter::EventChannel<flutter::EncodableValue>>(
          registrar->messenger(), "system_hotkeys/events",
          &flutter::StandardMethodCodec::GetInstance());
  events->SetStreamHandler(
      std::make_unique<
          flutter::StreamHandlerFunctions<flutter::EncodableValue>>(
          [raw](const flutter::EncodableValue*,
                std::unique_ptr<flutter::EventSink<flutter::EncodableValue>>&&
                    sink)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            raw->sink_ = std::move(sink);
            return nullptr;
          },
          [raw](const flutter::EncodableValue*)
              -> std::unique_ptr<
                  flutter::StreamHandlerError<flutter::EncodableValue>> {
            raw->sink_.reset();
            return nullptr;
          }));

  // The channels live as long as the registrar, like the plugin itself.
  methods.release();
  events.release();
  registrar->AddPlugin(std::move(plugin));
}

SystemHotkeysWindowsPlugin::SystemHotkeysWindowsPlugin(
    flutter::PluginRegistrarWindows* registrar)
    : registrar_(registrar) {
  window_proc_id_ = registrar_->RegisterTopLevelWindowProcDelegate(
      [this](HWND hwnd, UINT message, WPARAM wparam, LPARAM lparam) {
        return HandleWindowProc(hwnd, message, wparam, lparam);
      });
}

SystemHotkeysWindowsPlugin::~SystemHotkeysWindowsPlugin() {
  UnregisterAll();
  registrar_->UnregisterTopLevelWindowProcDelegate(window_proc_id_);
}

HWND SystemHotkeysWindowsPlugin::Window() const {
  auto* view = registrar_->GetView();
  if (!view) return nullptr;
  return GetAncestor(view->GetNativeWindow(), GA_ROOT);
}

void SystemHotkeysWindowsPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
  const auto& method = call.method_name();
  if (method == "register") {
    const auto* id = args ? Arg<std::string>(*args, "id") : nullptr;
    if (!id) {
      result->Error("bad_args", "id, usage and modifiers");
      return;
    }
    result->Success(flutter::EncodableValue(
        Register(*id, Number(*args, "usage"), Number(*args, "modifiers"))));
  } else if (method == "unregister") {
    if (const auto* id = args ? Arg<std::string>(*args, "id") : nullptr) {
      Unregister(*id);
    }
    result->Success();
  } else if (method == "unregisterAll") {
    UnregisterAll();
    result->Success();
  } else {
    result->NotImplemented();
  }
}

std::string SystemHotkeysWindowsPlugin::Register(const std::string& id,
                                                 int64_t usage, int64_t bits) {
  Unregister(id);
  const UINT key = VirtualKey(usage);
  const HWND window = Window();
  if (bits <= 0 || key == 0 || !window) return "unsupported";

  // Application hot key ids live in 0x0000 to 0xBFFF.
  if (next_number_ > 0xBFFF) return "unsupported";
  const int number = next_number_++;
  if (!RegisterHotKey(window, number, WindowsModifiers(bits), key)) {
    return GetLastError() == ERROR_HOTKEY_ALREADY_REGISTERED ? "conflict"
                                                             : "unsupported";
  }
  numbers_[id] = number;
  ids_[number] = id;
  return "bound";
}

void SystemHotkeysWindowsPlugin::Unregister(const std::string& id) {
  auto it = numbers_.find(id);
  if (it == numbers_.end()) return;
  if (const HWND window = Window()) UnregisterHotKey(window, it->second);
  ids_.erase(it->second);
  numbers_.erase(it);
}

void SystemHotkeysWindowsPlugin::UnregisterAll() {
  std::vector<std::string> all;
  for (const auto& entry : numbers_) all.push_back(entry.first);
  for (const auto& id : all) Unregister(id);
}

std::optional<LRESULT> SystemHotkeysWindowsPlugin::HandleWindowProc(
    HWND, UINT message, WPARAM wparam, LPARAM) {
  if (message != WM_HOTKEY) return std::nullopt;
  auto it = ids_.find(static_cast<int>(wparam));
  if (it == ids_.end()) return std::nullopt;
  if (sink_) sink_->Success(flutter::EncodableValue(it->second));
  return 0;
}

}  // namespace system_hotkeys_windows
