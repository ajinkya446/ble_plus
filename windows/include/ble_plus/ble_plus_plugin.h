// ============================================================================
// Public header of the Windows plugin (canonical).
// ----------------------------------------------------------------------------
// Flutter generates the runner's generated_plugin_registrant.cc expecting an
// include <ble_plus/ble_plus_plugin.h> and a `BlePlusPluginRegisterWith-
// Registrar` symbol (this include_dir reaches the runner via
// example/windows/runner/CMakeLists.txt, which adds the include dirs of all
// plugins). This header is the public face of the DLL: the rest of the
// implementation lives in windows/ble_plus_plugin.{h,cpp}.
//
// Note: the internal header (ble_plus_plugin.h of the .cpp) uses a different
// include guard (BLE_PLUS_BLE_PLUS_PLUGIN_H_) so it does not collide with
// this guard.
// ============================================================================
#ifndef FLUTTER_PLUGIN_BLE_PLUS_PLUGIN_H_
#define FLUTTER_PLUGIN_BLE_PLUS_PLUGIN_H_

#include <flutter_plugin_registrar.h>

// Exposes the symbol as dllexport when compiled inside the plugin DLL
// (FLUTTER_PLUGIN_IMPL is defined by windows/CMakeLists.txt) and as
// dllimport for whoever consumes the DLL.
#ifdef FLUTTER_PLUGIN_IMPL
#define FLUTTER_PLUGIN_EXPORT __declspec(dllexport)
#else
#define FLUTTER_PLUGIN_EXPORT __declspec(dllimport)
#endif

#if defined(__cplusplus)
extern "C" {
#endif

// Registers the plugin with the low-level Flutter Desktop registrar.
FLUTTER_PLUGIN_EXPORT void BlePlusPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar);

#if defined(__cplusplus)
}  // extern "C"
#endif

#endif  // FLUTTER_PLUGIN_BLE_PLUS_PLUGIN_H_
