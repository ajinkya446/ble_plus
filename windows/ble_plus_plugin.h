#ifndef FLUTTER_PLUGIN_BLE_PLUS_PLUGIN_H_
#define FLUTTER_PLUGIN_BLE_PLUS_PLUGIN_H_

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>

#include <memory>
#include <map>
#include <string>
#include <mutex>

// WinRT headers
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Devices.Bluetooth.h>
#include <winrt/Windows.Devices.Bluetooth.GenericAttributeProfile.h>
#include <winrt/Windows.Devices.Bluetooth.Advertisement.h>
#include <winrt/Windows.Devices.Enumeration.h>
#include <winrt/Windows.Storage.Streams.h>

namespace ble_plus {

using namespace winrt;
using namespace Windows::Devices::Bluetooth;
using namespace Windows::Devices::Bluetooth::GenericAttributeProfile;
using namespace Windows::Devices::Bluetooth::Advertisement;
using namespace Windows::Storage::Streams;

class BlePlusPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows *registrar);

  BlePlusPlugin();
  virtual ~BlePlusPlugin();

  BlePlusPlugin(const BlePlusPlugin&) = delete;
  BlePlusPlugin& operator=(const BlePlusPlugin&) = delete;

  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue> &method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

 private:
  // Scanning
  BluetoothLEAdvertisementWatcher watcher_{nullptr};
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> scan_sink_;

  // Connections
  std::map<std::string, BluetoothLEDevice> devices_;
  std::map<std::string, std::vector<GattDeviceService>> device_services_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> connection_sink_;
  std::unique_ptr<flutter::EventSink<flutter::EncodableValue>> char_sink_;
  std::mutex mutex_;

  void StartScan(const flutter::EncodableMap& args);
  void StopScan();
  void Connect(const std::string& device_id,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void Disconnect(const std::string& device_id);
  void DiscoverServices(const std::string& device_id,
                        std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void ReadCharacteristic(const std::string& device_id,
                          const std::string& service_uuid,
                          const std::string& char_uuid,
                          std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void WriteCharacteristic(const std::string& device_id,
                           const std::string& service_uuid,
                           const std::string& char_uuid,
                           const std::vector<uint8_t>& value,
                           bool with_response,
                           std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);
  void SetNotification(const std::string& device_id,
                       const std::string& service_uuid,
                       const std::string& char_uuid,
                       bool enable,
                       std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  std::string GuidToString(const winrt::guid& g);
  winrt::guid StringToGuid(const std::string& s);
  GattCharacteristic FindCharacteristic(const std::string& device_id,
                                         const std::string& service_uuid,
                                         const std::string& char_uuid);
};

}  // namespace ble_plus

#endif  // FLUTTER_PLUGIN_BLE_PLUS_PLUGIN_H_
