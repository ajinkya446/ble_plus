#include "ble_plus_plugin.h"

#include <windows.h>
#include <VersionHelpers.h>

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <sstream>
#include <iomanip>
#include <algorithm>
#include <future>

namespace ble_plus {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::EncodableList;

void BlePlusPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  auto method_channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), "ble_plus/methods",
          &flutter::StandardMethodCodec::GetInstance());

  auto scan_channel =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar->messenger(), "ble_plus/scan",
          &flutter::StandardMethodCodec::GetInstance());

  auto connection_channel =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar->messenger(), "ble_plus/connection",
          &flutter::StandardMethodCodec::GetInstance());

  auto char_channel =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar->messenger(), "ble_plus/characteristic",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<BlePlusPlugin>();
  auto plugin_ptr = plugin.get();

  method_channel->SetMethodCallHandler(
      [plugin_ptr](const auto &call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  auto scan_handler = std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
      [plugin_ptr](const EncodableValue* args,
                   std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        plugin_ptr->scan_sink_ = std::move(sink);
        return nullptr;
      },
      [plugin_ptr](const EncodableValue* args)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        plugin_ptr->scan_sink_ = nullptr;
        return nullptr;
      });
  scan_channel->SetStreamHandler(std::move(scan_handler));

  auto conn_handler = std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
      [plugin_ptr](const EncodableValue* args,
                   std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        plugin_ptr->connection_sink_ = std::move(sink);
        return nullptr;
      },
      [plugin_ptr](const EncodableValue* args)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        plugin_ptr->connection_sink_ = nullptr;
        return nullptr;
      });
  connection_channel->SetStreamHandler(std::move(conn_handler));

  auto char_handler = std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
      [plugin_ptr](const EncodableValue* args,
                   std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        plugin_ptr->char_sink_ = std::move(sink);
        return nullptr;
      },
      [plugin_ptr](const EncodableValue* args)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        plugin_ptr->char_sink_ = nullptr;
        return nullptr;
      });
  char_channel->SetStreamHandler(std::move(char_handler));

  registrar->AddPlugin(std::move(plugin));
}

BlePlusPlugin::BlePlusPlugin() {
  winrt::init_apartment(winrt::apartment_type::single_threaded);
}

BlePlusPlugin::~BlePlusPlugin() {
  StopScan();
}

void BlePlusPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {

  const auto& method = method_call.method_name();
  const auto* args_ptr = std::get_if<EncodableMap>(method_call.arguments());
  EncodableMap args = args_ptr ? *args_ptr : EncodableMap{};

  if (method == "getAdapterState") {
    // Check if Bluetooth adapter is available
    try {
      auto adapter = BluetoothAdapter::GetDefaultAsync().get();
      if (adapter == nullptr) {
        result->Success(EncodableValue(1)); // unsupported
      } else if (!adapter.IsLowEnergySupported()) {
        result->Success(EncodableValue(1)); // unsupported
      } else {
        // Check radio state
        auto radio = adapter.GetRadioAsync().get();
        if (radio != nullptr && radio.State() == winrt::Windows::Devices::Radios::RadioState::On) {
          result->Success(EncodableValue(4)); // poweredOn
        } else {
          result->Success(EncodableValue(6)); // poweredOff
        }
      }
    } catch (...) {
      result->Success(EncodableValue(0)); // unknown
    }
  } else if (method == "startScan") {
    StartScan(args);
    result->Success(EncodableValue(nullptr));
  } else if (method == "stopScan") {
    StopScan();
    result->Success(EncodableValue(nullptr));
  } else if (method == "connect") {
    auto it = args.find(EncodableValue("deviceId"));
    if (it != args.end()) {
      Connect(std::get<std::string>(it->second), std::move(result));
    } else {
      result->Error("INVALID_ARGS", "deviceId required");
    }
  } else if (method == "disconnect") {
    auto it = args.find(EncodableValue("deviceId"));
    if (it != args.end()) {
      Disconnect(std::get<std::string>(it->second));
      result->Success(EncodableValue(nullptr));
    } else {
      result->Error("INVALID_ARGS", "deviceId required");
    }
  } else if (method == "discoverServices") {
    auto it = args.find(EncodableValue("deviceId"));
    if (it != args.end()) {
      DiscoverServices(std::get<std::string>(it->second), std::move(result));
    } else {
      result->Error("INVALID_ARGS", "deviceId required");
    }
  } else if (method == "readCharacteristic") {
    auto did = std::get<std::string>(args[EncodableValue("deviceId")]);
    auto sid = std::get<std::string>(args[EncodableValue("serviceUuid")]);
    auto cid = std::get<std::string>(args[EncodableValue("characteristicUuid")]);
    ReadCharacteristic(did, sid, cid, std::move(result));
  } else if (method == "writeCharacteristic") {
    auto did = std::get<std::string>(args[EncodableValue("deviceId")]);
    auto sid = std::get<std::string>(args[EncodableValue("serviceUuid")]);
    auto cid = std::get<std::string>(args[EncodableValue("characteristicUuid")]);
    auto val_list = std::get<EncodableList>(args[EncodableValue("value")]);
    std::vector<uint8_t> value;
    for (const auto& v : val_list) { value.push_back(static_cast<uint8_t>(std::get<int32_t>(v))); }
    auto wr = std::get<bool>(args[EncodableValue("withResponse")]);
    WriteCharacteristic(did, sid, cid, value, wr, std::move(result));
  } else if (method == "setNotification") {
    auto did = std::get<std::string>(args[EncodableValue("deviceId")]);
    auto sid = std::get<std::string>(args[EncodableValue("serviceUuid")]);
    auto cid = std::get<std::string>(args[EncodableValue("characteristicUuid")]);
    auto enable = std::get<bool>(args[EncodableValue("enable")]);
    SetNotification(did, sid, cid, enable, std::move(result));
  } else if (method == "requestMtu") {
    // Windows auto-negotiates MTU
    result->Success(EncodableValue(517));
  } else if (method == "getConnectedDevices") {
    EncodableList ids;
    for (const auto& pair : devices_) {
      ids.push_back(EncodableValue(pair.first));
    }
    result->Success(EncodableValue(ids));
  } else if (method == "createBond") {
    // Windows handles pairing automatically during GATT operations
    result->Success(EncodableValue(nullptr));
  } else if (method == "removeBond") {
    result->Error("UNSUPPORTED", "Windows does not support programmatic bond removal");
  } else if (method == "getBondState") {
    // Check if device is paired via WinRT
    auto it = args.find(EncodableValue("deviceId"));
    if (it != args.end()) {
      try {
        auto device_id = std::get<std::string>(it->second);
        auto dev_it = devices_.find(device_id);
        if (dev_it != devices_.end()) {
          auto info = dev_it->second.DeviceInformation();
          auto pairing = info.Pairing();
          result->Success(EncodableValue(pairing.IsPaired() ? 2 : 0)); // 2=bonded, 0=none
        } else {
          result->Success(EncodableValue(0));
        }
      } catch (...) {
        result->Success(EncodableValue(0));
      }
    } else {
      result->Success(EncodableValue(0));
    }
  } else {
    result->NotImplemented();
  }
}

// ═══════════════════════════════════════════════════════════
// SCANNING
// ═══════════════════════════════════════════════════════════

void BlePlusPlugin::StartScan(const EncodableMap& args) {
  StopScan(); // Stop any existing scan

  watcher_ = BluetoothLEAdvertisementWatcher();
  watcher_.ScanningMode(BluetoothLEScanningMode::Active);

  watcher_.Received([this](BluetoothLEAdvertisementWatcher const&,
                           BluetoothLEAdvertisementReceivedEventArgs const& eventArgs) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (!scan_sink_) return;

    auto address = eventArgs.BluetoothAddress();
    std::ostringstream addr_stream;
    addr_stream << std::hex << std::setfill('0');
    for (int i = 5; i >= 0; i--) {
      addr_stream << std::setw(2) << ((address >> (i * 8)) & 0xFF);
      if (i > 0) addr_stream << ":";
    }
    auto device_id = addr_stream.str();
    std::transform(device_id.begin(), device_id.end(), device_id.begin(), ::toupper);

    auto ad = eventArgs.Advertisement();
    std::string name;
    if (!ad.LocalName().empty()) {
      name = winrt::to_string(ad.LocalName());
    }

    EncodableList service_uuids;
    for (const auto& uuid : ad.ServiceUuids()) {
      service_uuids.push_back(EncodableValue(GuidToString(uuid)));
    }

    EncodableMap mfg_data;
    for (const auto& section : ad.ManufacturerData()) {
      auto data = section.Data();
      auto reader = DataReader::FromBuffer(data);
      std::vector<uint8_t> bytes(reader.UnconsumedBufferLength());
      if (!bytes.empty()) reader.ReadBytes(bytes);
      EncodableList byte_list;
      for (auto b : bytes) byte_list.push_back(EncodableValue(static_cast<int32_t>(b)));
      mfg_data[EncodableValue(static_cast<int32_t>(section.CompanyId()))] = EncodableValue(byte_list);
    }

    EncodableMap result;
    result[EncodableValue("deviceId")] = EncodableValue(device_id);
    result[EncodableValue("name")] = name.empty() ? EncodableValue() : EncodableValue(name);
    result[EncodableValue("rssi")] = EncodableValue(static_cast<int32_t>(eventArgs.RawSignalStrengthInDBm()));
    result[EncodableValue("timestampMs")] = EncodableValue(static_cast<int64_t>(
        std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::system_clock::now().time_since_epoch()).count()));
    result[EncodableValue("connectable")] = EncodableValue(true);
    result[EncodableValue("serviceUuids")] = EncodableValue(service_uuids);
    result[EncodableValue("manufacturerData")] = EncodableValue(mfg_data);
    result[EncodableValue("serviceData")] = EncodableValue(EncodableMap{});

    scan_sink_->Success(EncodableValue(result));
  });

  watcher_.Start();
}

void BlePlusPlugin::StopScan() {
  if (watcher_ != nullptr) {
    try { watcher_.Stop(); } catch (...) {}
    watcher_ = nullptr;
  }
}

// ═══════════════════════════════════════════════════════════
// CONNECTION
// ═══════════════════════════════════════════════════════════

void BlePlusPlugin::Connect(const std::string& device_id,
                            std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  // Parse MAC address to uint64
  uint64_t address = 0;
  std::string addr = device_id;
  addr.erase(std::remove(addr.begin(), addr.end(), ':'), addr.end());
  address = std::stoull(addr, nullptr, 16);

  try {
    auto device = BluetoothLEDevice::FromBluetoothAddressAsync(address).get();
    if (device == nullptr) {
      result->Error("NOT_FOUND", "Device not found");
      return;
    }

    devices_[device_id] = device;

    if (connection_sink_) {
      EncodableMap event;
      event[EncodableValue("deviceId")] = EncodableValue(device_id);
      event[EncodableValue("state")] = EncodableValue(2); // connected
      connection_sink_->Success(EncodableValue(event));
    }

    result->Success(EncodableValue(nullptr));
  } catch (const std::exception& e) {
    result->Error("CONNECTION_FAILED", e.what());
  }
}

void BlePlusPlugin::Disconnect(const std::string& device_id) {
  devices_.erase(device_id);
  device_services_.erase(device_id);

  if (connection_sink_) {
    EncodableMap event;
    event[EncodableValue("deviceId")] = EncodableValue(device_id);
    event[EncodableValue("state")] = EncodableValue(0); // disconnected
    connection_sink_->Success(EncodableValue(event));
  }
}

// ═══════════════════════════════════════════════════════════
// GATT
// ═══════════════════════════════════════════════════════════

void BlePlusPlugin::DiscoverServices(const std::string& device_id,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  auto it = devices_.find(device_id);
  if (it == devices_.end()) {
    result->Error("NOT_CONNECTED", "Not connected");
    return;
  }

  try {
    auto services_result = it->second.GetGattServicesAsync().get();
    if (services_result.Status() != GattCommunicationStatus::Success) {
      result->Error("GATT_ERROR", "Failed to get services");
      return;
    }

    EncodableList services_list;
    device_services_[device_id].clear();

    for (const auto& service : services_result.Services()) {
      device_services_[device_id].push_back(service);
      auto service_uuid = GuidToString(service.Uuid());

      auto chars_result = service.GetCharacteristicsAsync().get();
      EncodableList chars_list;

      if (chars_result.Status() == GattCommunicationStatus::Success) {
        for (const auto& ch : chars_result.Characteristics()) {
          auto props = static_cast<int32_t>(ch.CharacteristicProperties());
          EncodableMap char_map;
          char_map[EncodableValue("uuid")] = EncodableValue(GuidToString(ch.Uuid()));
          char_map[EncodableValue("serviceUuid")] = EncodableValue(service_uuid);
          char_map[EncodableValue("properties")] = EncodableValue(props);
          char_map[EncodableValue("descriptors")] = EncodableValue(EncodableList{});
          chars_list.push_back(EncodableValue(char_map));
        }
      }

      EncodableMap service_map;
      service_map[EncodableValue("uuid")] = EncodableValue(service_uuid);
      service_map[EncodableValue("isPrimary")] = EncodableValue(true);
      service_map[EncodableValue("characteristics")] = EncodableValue(chars_list);
      service_map[EncodableValue("includedServices")] = EncodableValue(EncodableList{});
      services_list.push_back(EncodableValue(service_map));
    }

    result->Success(EncodableValue(services_list));
  } catch (const std::exception& e) {
    result->Error("GATT_ERROR", e.what());
  }
}

void BlePlusPlugin::ReadCharacteristic(const std::string& device_id,
    const std::string& service_uuid, const std::string& char_uuid,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  try {
    auto ch = FindCharacteristic(device_id, service_uuid, char_uuid);
    if (ch == nullptr) {
      result->Error("NOT_FOUND", "Characteristic not found");
      return;
    }

    auto read_result = ch.ReadValueAsync().get();
    if (read_result.Status() != GattCommunicationStatus::Success) {
      result->Error("GATT_ERROR", "Read failed");
      return;
    }

    auto reader = DataReader::FromBuffer(read_result.Value());
    std::vector<uint8_t> bytes(reader.UnconsumedBufferLength());
    if (!bytes.empty()) reader.ReadBytes(bytes);

    EncodableList value;
    for (auto b : bytes) value.push_back(EncodableValue(static_cast<int32_t>(b)));
    result->Success(EncodableValue(value));
  } catch (const std::exception& e) {
    result->Error("GATT_ERROR", e.what());
  }
}

void BlePlusPlugin::WriteCharacteristic(const std::string& device_id,
    const std::string& service_uuid, const std::string& char_uuid,
    const std::vector<uint8_t>& value, bool with_response,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  try {
    auto ch = FindCharacteristic(device_id, service_uuid, char_uuid);
    if (ch == nullptr) {
      result->Error("NOT_FOUND", "Characteristic not found");
      return;
    }

    auto writer = DataWriter();
    writer.WriteBytes(value);
    auto buffer = writer.DetachBuffer();

    auto option = with_response
        ? GattWriteOption::WriteWithResponse
        : GattWriteOption::WriteWithoutResponse;

    auto write_result = ch.WriteValueAsync(buffer, option).get();
    if (write_result != GattCommunicationStatus::Success) {
      result->Error("GATT_ERROR", "Write failed");
      return;
    }

    result->Success(EncodableValue(nullptr));
  } catch (const std::exception& e) {
    result->Error("GATT_ERROR", e.what());
  }
}

void BlePlusPlugin::SetNotification(const std::string& device_id,
    const std::string& service_uuid, const std::string& char_uuid,
    bool enable,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  try {
    auto ch = FindCharacteristic(device_id, service_uuid, char_uuid);
    if (ch == nullptr) {
      result->Error("NOT_FOUND", "Characteristic not found");
      return;
    }

    auto cccd_value = enable
        ? GattClientCharacteristicConfigurationDescriptorValue::Notify
        : GattClientCharacteristicConfigurationDescriptorValue::None;

    auto status = ch.WriteClientCharacteristicConfigurationDescriptorAsync(cccd_value).get();
    if (status != GattCommunicationStatus::Success) {
      result->Error("GATT_ERROR", "Failed to set notification");
      return;
    }

    if (enable) {
      ch.ValueChanged([this, device_id, service_uuid, char_uuid](
          GattCharacteristic const&, GattValueChangedEventArgs const& args) {
        if (!char_sink_) return;
        auto reader = DataReader::FromBuffer(args.CharacteristicValue());
        std::vector<uint8_t> bytes(reader.UnconsumedBufferLength());
        if (!bytes.empty()) reader.ReadBytes(bytes);

        EncodableList value;
        for (auto b : bytes) value.push_back(EncodableValue(static_cast<int32_t>(b)));

        EncodableMap event;
        event[EncodableValue("deviceId")] = EncodableValue(device_id);
        event[EncodableValue("serviceUuid")] = EncodableValue(service_uuid);
        event[EncodableValue("characteristicUuid")] = EncodableValue(char_uuid);
        event[EncodableValue("value")] = EncodableValue(value);
        char_sink_->Success(EncodableValue(event));
      });
    }

    result->Success(EncodableValue(nullptr));
  } catch (const std::exception& e) {
    result->Error("GATT_ERROR", e.what());
  }
}

// ═══════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════

GattCharacteristic BlePlusPlugin::FindCharacteristic(
    const std::string& device_id,
    const std::string& service_uuid,
    const std::string& char_uuid) {
  auto it = devices_.find(device_id);
  if (it == devices_.end()) return nullptr;

  auto service_guid = StringToGuid(service_uuid);
  auto char_guid = StringToGuid(char_uuid);

  auto services_result = it->second.GetGattServicesForUuidAsync(service_guid).get();
  if (services_result.Status() != GattCommunicationStatus::Success || services_result.Services().Size() == 0) {
    return nullptr;
  }

  auto chars_result = services_result.Services().GetAt(0).GetCharacteristicsForUuidAsync(char_guid).get();
  if (chars_result.Status() != GattCommunicationStatus::Success || chars_result.Characteristics().Size() == 0) {
    return nullptr;
  }

  return chars_result.Characteristics().GetAt(0);
}

std::string BlePlusPlugin::GuidToString(const winrt::guid& g) {
  char buf[40];
  snprintf(buf, sizeof(buf),
           "%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
           g.Data1, g.Data2, g.Data3,
           g.Data4[0], g.Data4[1], g.Data4[2], g.Data4[3],
           g.Data4[4], g.Data4[5], g.Data4[6], g.Data4[7]);
  return std::string(buf);
}

winrt::guid BlePlusPlugin::StringToGuid(const std::string& s) {
  // Parse UUID string like "0000180d-0000-1000-8000-00805f9b34fb"
  winrt::guid g;
  unsigned int d1, d2, d3;
  unsigned int d4[8];
  sscanf(s.c_str(), "%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
         &d1, &d2, &d3,
         &d4[0], &d4[1], &d4[2], &d4[3],
         &d4[4], &d4[5], &d4[6], &d4[7]);
  g.Data1 = d1;
  g.Data2 = static_cast<uint16_t>(d2);
  g.Data3 = static_cast<uint16_t>(d3);
  for (int i = 0; i < 8; i++) g.Data4[i] = static_cast<uint8_t>(d4[i]);
  return g;
}

}  // namespace ble_plus
