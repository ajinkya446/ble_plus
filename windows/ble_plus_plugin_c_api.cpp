// ============================================================================
// ble_plus_plugin_c_api.cpp — C API entry point of the Windows plugin
// ----------------------------------------------------------------------------
// The generated_plugin_registrant.cc (which Flutter generates in the runner)
// expects a `BlePlusPluginRegisterWithRegistrar` symbol declared in the public
// header <ble_plus/ble_plus_plugin.h>. This translation unit connects that
// symbol with the real C++ class (ble_plus::BlePlusPlugin).
//
// HISTORY NOTE: the public header used to be named ble_plus_plugin_c_api.h
// and the symbol carried a `CApi` suffix; the generated registrant could not
// find it (C1083). It was renamed to the canonical form that Flutter expects.
// ============================================================================
#include "include/ble_plus/ble_plus_plugin.h"

#include <flutter/plugin_registrar_windows.h>

#include "ble_plus_plugin.h"

// Implements the symbol expected by the generated_plugin_registrant.cc:
// converts the low-level registrar (FlutterDesktopPluginRegistrarRef) into the
// PluginRegistrarWindows used by the plugin class.
void BlePlusPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  ble_plus::BlePlusPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
