#ifndef FLUTTER_PLUGIN_SYSTEM_HOTKEYS_WINDOWS_PLUGIN_H_
#define FLUTTER_PLUGIN_SYSTEM_HOTKEYS_WINDOWS_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <windows.h>

#include <map>
#include <memory>
#include <optional>
#include <string>

namespace system_hotkeys_windows {

// System-wide shortcuts through RegisterHotKey.
//
// The registration API, not a low-level keyboard hook: the system delivers
// WM_HOTKEY for the bound combinations and nothing else, so no other key ever
// reaches this process. A combination another app holds fails with
// ERROR_HOTKEY_ALREADY_REGISTERED and is reported as a conflict.
//
// The channels are members, so they go with the plugin and no message can
// reach a plugin that is gone.
class SystemHotkeysWindowsPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);

  explicit SystemHotkeysWindowsPlugin(
      flutter::PluginRegistrarWindows* registrar);
  ~SystemHotkeysWindowsPlugin() override;

  SystemHotkeysWindowsPlugin(const SystemHotkeysWindowsPlugin&) = delete;
  SystemHotkeysWindowsPlugin& operator=(const SystemHotkeysWindowsPlugin&) =
      delete;

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::string Register(const std::string& id, int64_t usage, int64_t bits);
  void Unregister(const std::string& id);
  void UnregisterAll();
  std::optional<LRESULT> HandleWindowProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam);
  HWND Window() const;

  flutter::PluginRegistrarWindows* registrar_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> methods_;
  std::unique_ptr<flutter::EventChannel<flutter::EncodableValue>> events_;
  int window_proc_id_ = -1;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> sink_;
  std::map<std::string, int> numbers_;
  std::map<int, std::string> ids_;
};

}  // namespace system_hotkeys_windows

#endif  // FLUTTER_PLUGIN_SYSTEM_HOTKEYS_WINDOWS_PLUGIN_H_
