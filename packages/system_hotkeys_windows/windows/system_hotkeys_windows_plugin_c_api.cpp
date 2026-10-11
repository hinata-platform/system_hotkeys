#include "include/system_hotkeys_windows/system_hotkeys_windows_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "system_hotkeys_windows_plugin.h"

void SystemHotkeysWindowsPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  system_hotkeys_windows::SystemHotkeysWindowsPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
