#include "include/ble_plus/ble_plus_plugin_c_api.h"

#include <flutter/plugin_registrar_windows.h>

#include "ble_plus_plugin.h"

void BlePlusPluginCApiRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  ble_plus::BlePlusPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
