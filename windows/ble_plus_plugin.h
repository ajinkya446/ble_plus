#ifndef BLE_PLUS_BLE_PLUS_PLUGIN_H_
#define BLE_PLUS_BLE_PLUS_PLUGIN_H_

// ============================================================================
// ble_plus_plugin.h — Windows BLE plugin (C++/WinRT)
// ----------------------------------------------------------------------------
// This header declares the BlePlusPlugin class, the core of the Windows
// support for the `ble_plus` package. It talks to Windows.Devices.Bluetooth
// through C++/WinRT and exposes the same channel contract as the rest of the
// platforms:
//
//   - "ble_plus/methods"        : MethodChannel with startScan, connect,
//                                 discoverServices, read/write, setNotification,
//                                 requestMtu, etc.
//   - "ble_plus/scan"           : EventChannel with the advertisements.
//   - "ble_plus/connection"     : EventChannel with the connection changes.
//   - "ble_plus/characteristic" : EventChannel with the GATT notifications.
//   - "ble_plus/log"            : EventChannel of native logs → Dart (live
//                                 diagnostics; see BlePlusPlugin::Log).
//
// THREADING (IMPORTANT — do not change without understanding this):
//   * The Flutter engine creates the plugin on the platform thread (an STA
//     thread, see the constructor comment). MethodCalls arrive on that thread.
//   * WinRT invokes the callbacks (AdvertisementWatcher::Received,
//     GattCharacteristic::ValueChanged) on thread pool threads.
//   * The EventSinks (scan_sink_, connection_sink_, char_sink_, log_sink_) are
//     NEVER touched outside the platform thread: every delivery goes through
//     RunOnPlatformThread (message-only window + PostMessage).
//   * Asynchronous operations run on std::thread(...).detach() instead of
//     cppwinrt coroutines: the coroutine + engine STA thread combo caused
//     std::terminate()/abort(). DO NOT revert to fire_and_forget.
//
// ERRORS:
//   * All operations catch exceptions with a triple try/catch
//     (winrt::hresult_error → std::exception → catch(...)). winrt::hresult_error
//     does NOT inherit from std::exception, so a std::exception catch only let
//     WinRT exceptions escape → std::terminate.
//   * Errors are reported to Dart with SendError(...), which attaches
//     structured details (stage, deviceId, HRESULT, GATT status, protocolError)
//     so mapPlatformException (lib/src/errors/error_mapper.dart) propagates
//     them in the BleError object the public API promises to throw.
// ============================================================================

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <atomic>
#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <vector>

// WinRT headers — Windows BLE lives in these namespaces.
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Devices.Radios.h>
#include <winrt/Windows.Storage.Streams.h>

namespace ble_plus {

using namespace winrt;
using namespace Windows::Devices::Bluetooth;
using namespace Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace Windows::Devices::Bluetooth::Advertisement;
using namespace Windows::Storage::Streams;

// ----------------------------------------------------------------------------
// ErrorDetails — structured information that travels as the error `details` of
// the MethodChannel to Dart (see SendError in the .cpp).
// ----------------------------------------------------------------------------
struct ErrorDetails {
  // Error code of the Dart contract: "TIMEOUT", "CONNECTION_FAILED",
  // "NOT_CONNECTED", "NOT_FOUND", "GATT_ERROR", "INVALID_ARGS"...
  std::string code;
  // Label of the exact point where it failed, e.g. "connect:gattSession",
  // "discoverServices:unreachable", "readCharacteristic:status".
  std::string stage;
  // Readable message (used as the `message` of the PlatformException).
  std::string message;
  // MAC address of the involved device (empty if not applicable).
  std::string device_id;
  // Raw HRESULT of the WinRT exception (0 if there is no WinRT exception).
  int32_t hresult = 0;
  // GattCommunicationStatus returned by the operation (-1 if not applicable).
  int32_t gatt_status = -1;
  // Device ProtocolError (e.g. protocolError=7 on the 2A19 read) (-1 if not
  // applicable).
  int32_t protocol_error = -1;
};

class BlePlusPlugin : public flutter::Plugin {
 public:
  // Registers the plugin and its channels with the Flutter registrar. Invoked
  // from ble_plus_plugin_c_api.cpp (symbol BlePlusPluginRegisterWithRegistrar
  // expected by the generated_plugin_registrant.cc).
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  BlePlusPlugin();
  virtual ~BlePlusPlugin();

  // Not copyable: it owns sinks, a watcher and maps that cannot be duplicated.
  BlePlusPlugin(const BlePlusPlugin&) = delete;
  BlePlusPlugin& operator=(const BlePlusPlugin&) = delete;

  // Single entry point of the MethodChannel "ble_plus/methods".
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  // ==========================================================================
  // STATE AND SINKS
  // ==========================================================================

  // Active advertisement watcher (only one scan at a time on Windows). It is
  // restarted on each StartScan and stopped in StopScan/~BlePlusPlugin.
  BluetoothLEAdvertisementWatcher watcher_{nullptr};
  // Sink of the EventChannel "ble_plus/scan". Only touched on the platform
  // thread (assigned here from the stream handler and read inside
  // RunOnPlatformThread in the Received callback).
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> scan_sink_;

  // Active connections per device_id (MAC address in lowercase with ':').
  // Populated by Connect and consumed by DiscoverServices/getConnectedDevices.
  // The BluetoothLEDevice object keeps the WinRT object alive.
  std::map<std::string, BluetoothLEDevice> devices_;
  // Discovered GattDeviceService handles per device. Kept to keep the GATT
  // objects alive (if destroyed, the device may close the connection).
  std::map<std::string, std::vector<GattDeviceService>> device_services_;
  // Names accumulated per address (the name usually arrives in the scan
  // response, in a separate event with the same address). Accumulated in the
  // Received callback so it can be reused in later events.
  std::map<std::string, std::string> device_names_;
  // GATT sessions keeping the connection active (MaintainConnection(true)).
  // Windows connects lazily; without GattSession the first GATT operation may
  // return Unreachable. Kept to hold the link alive.
  std::map<std::string, GattSession> device_sessions_;
  // Cache of discovered characteristics: key "device|serviceUuid|charUuid".
  // Avoids re-querying the GATT stack by UUID (which aborts on the Generic
  // Attribute Service, 1801, when accessing Service Changed). Populated in
  // DiscoverServices, read by FindCharacteristic and cleared in Disconnect.
  std::map<std::string, GattCharacteristic> device_characteristics_;
  // Sink of the EventChannel "ble_plus/connection".
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> connection_sink_;
  // Sink of the EventChannel "ble_plus/characteristic" (GATT notifications).
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> char_sink_;
  // Sink of the EventChannel "ble_plus/log" (native logs → Dart). If nobody
  // listens (log_sink_ == nullptr), Log() emits nothing and there is no
  // overhead.
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> log_sink_;
  // Class-wide mutex: protects devices_, device_services_, device_names_,
  // device_sessions_, device_characteristics_ and the sinks.
  std::mutex mutex_;

  // ==========================================================================
  // DISPATCH TO THE PLATFORM THREAD
  // ==========================================================================
  // The current thread is detected at runtime: if it does not match the
  // platform one (captured in the constructor), the action is dispatched with
  // PostMessage to a message-only window created on the platform thread. Its
  // WndProc runs on that thread's message pump and executes the action.
  flutter::PluginRegistrarWindows* registrar_ = nullptr;
  unsigned long platform_thread_id_ = 0;
  HWND platform_hwnd_ = nullptr;
  UINT dispatch_message_ = 0;
  static LRESULT CALLBACK DispatchWndProc(HWND hwnd, UINT message,
                                          WPARAM wparam, LPARAM lparam);
  // Template to accept lambdas with move-only captures (results).
  template <typename F>
  void RunOnPlatformThread(F&& action);

  // Serialization of GATT operations per device (Windows only allows one
  // pending operation at a time per device). Protects the mutex map; each
  // operation locks its device's mutex.
  std::mutex devices_mutex_;
  std::map<std::string, std::shared_ptr<std::mutex>> device_gatt_mutex_;
  std::shared_ptr<std::mutex> GetDeviceGattMutex(const std::string& device_id);

  // ==========================================================================
  // ADAPTER / SCANNING
  // ==========================================================================
  void StartScan(const flutter::EncodableMap& args);
  void StopScan();

  void GetAdapterState(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void RequestEnable(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // ==========================================================================
  // CONNECTION / GATT
  // ==========================================================================
  void Connect(
      const std::string& device_id,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Disconnect(const std::string& device_id);
  void DiscoverServices(
      const std::string& device_id,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ReadCharacteristic(
      const std::string& device_id,
      const std::string& service_uuid,
      const std::string& char_uuid,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void WriteCharacteristic(
      const std::string& device_id,
      const std::string& service_uuid,
      const std::string& char_uuid,
      const std::vector<uint8_t>& value,
      bool with_response,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetNotification(
      const std::string& device_id,
      const std::string& service_uuid,
      const std::string& char_uuid,
      bool enable,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  // ==========================================================================
  // HELPERS
  // ==========================================================================
  std::string GuidToString(const winrt::guid& g);
  winrt::guid StringToGuid(const std::string& s);
  GattCharacteristic FindCharacteristic(const std::string& device_id,
                                        const std::string& service_uuid,
                                        const std::string& char_uuid);

  // Sends an error to the MethodChannel with structured details (ErrorDetails)
  // as the third argument of result->Error(...). Performs the send on the
  // platform thread (safe from any thread). See error_mapper.dart.
  void SendError(
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result,
      const ErrorDetails& details);

  // Emits a log entry to the EventChannel "ble_plus/log" if a sink is
  // subscribed (log_sink_ != nullptr). `level` is one of the kLog* constants
  // of the .cpp (0=verbose, 1=debug, 2=info, 3=warning, 4=error) and must
  // match BleLogLevel in lib/src/ble_logger.dart. Safe from any thread.
  void Log(int level, const std::string& tag, const std::string& message);
};

}  // namespace ble_plus

#endif  // BLE_PLUS_BLE_PLUS_PLUGIN_H_
