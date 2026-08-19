#include "ble_plus_plugin.h"

#include <windows.h>
#include <VersionHelpers.h>

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <flutter/standard_method_codec.h>

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <exception>
#include <iomanip>
#include <memory>
#include <optional>
#include <sstream>
#include <thread>

namespace ble_plus {

using flutter::EncodableMap;
using flutter::EncodableValue;
using flutter::EncodableList;

namespace {

// Native log levels. MUST match the BleLogLevel enum in
// lib/src/ble_logger.dart (0=verbose, 1=debug, 2=info, 3=warning, 4=error).
// Level filtering is done on the Dart side; here entries are only labeled.
constexpr int kLogVerbose = 0;
constexpr int kLogDebug = 1;
constexpr int kLogInfo = 2;
constexpr int kLogWarning = 3;
constexpr int kLogError = 4;

// Awaits a WinRT async operation with a timeout without blocking the UI.
// Returns std::nullopt if the operation does not complete within [timeout].
//
// IMPROVEMENT IMPLEMENTED: a new thread
// used to be launched per operation with std::async and the result was fetched
// with get() on that unattended thread. That had two problems:
//   1. If the operation aborted the CRT (the discoverServices crash), the abort
//      happened OUTSIDE the try/catch of the plugin thread.
//   2. On timeout the std::future destructor BLOCKED until the task finished
//      (hanging detach threads if Cancel() did not interrupt get()).
// Now it polls operation.Status() on the SAME plugin thread: no extra threads,
// deterministic timeouts and the caller's try/catch covering any real WinRT
// exception.
template <typename T>
std::optional<T> AwaitWithTimeout(
    winrt::Windows::Foundation::IAsyncOperation<T> operation,
    std::chrono::milliseconds timeout) {
  try {
    const auto deadline = std::chrono::steady_clock::now() + timeout;
    while (std::chrono::steady_clock::now() < deadline) {
      switch (operation.Status()) {
        case winrt::Windows::Foundation::AsyncStatus::Completed:
          return operation.GetResults();
        case winrt::Windows::Foundation::AsyncStatus::Error:
        case winrt::Windows::Foundation::AsyncStatus::Canceled:
          // The operation failed or was canceled; GetResults() would throw
          // hresult_error.
          return std::nullopt;
        default:
          break;  // Started: keep waiting.
      }
      std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
    // Timeout: try to cancel the pending WinRT operation so the device is not
    // left with a half-finished operation.
    try {
      operation.Cancel();
    } catch (...) {
    }
    return std::nullopt;
  } catch (...) {
    return std::nullopt;
  }
}

// Task dispatchable to the platform thread that may hold move-only captures
// (e.g. unique_ptr of MethodResult/EventSink). Since std::function requires
// copyable, a polymorphic base is used: RunOnPlatformThread instantiates
// PlatformTaskImpl<F> and the WndProc runs and deletes the object.
struct PlatformTask {
  virtual ~PlatformTask() = default;
  virtual void Run() = 0;
};

template <typename F>
struct PlatformTaskImpl final : PlatformTask {
  explicit PlatformTaskImpl(F&& fn) : fn(std::move(fn)) {}
  void Run() override { fn(); }
  F fn;
};

// Message id of the message-only window used to dispatch to the platform
// thread (global because the WndProc is static).
UINT g_dispatch_message = 0;

// Creates an ErrorDetails with the essential fields (hresult=0, gatt_status=-1
// and protocol_error=-1 by default). Extra fields are filled by hand where
// needed (e.g. in catch blocks with WinRT exceptions).
ErrorDetails MakeError(std::string code, std::string stage, std::string message) {
  ErrorDetails d;
  d.code = std::move(code);
  d.stage = std::move(stage);
  d.message = std::move(message);
  return d;
}

}  // namespace

void BlePlusPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows *registrar) {
  // Main MethodChannel: synchronous operations (scan/connect/GATT).
  auto method_channel =
      std::make_unique<flutter::MethodChannel<EncodableValue>>(
          registrar->messenger(), "ble_plus/methods",
          &flutter::StandardMethodCodec::GetInstance());

  // EventChannels: async events are delivered here (streams).
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

  // Native logs EventChannel → Dart. It is live diagnostics: BleCentral (Dart)
  // subscribes to it and relays entries to the user's BleLogger, so the
  // scan/connect/discover steps are visible in the console/app without going
  // through the method channel.
  auto log_channel =
      std::make_unique<flutter::EventChannel<EncodableValue>>(
          registrar->messenger(), "ble_plus/log",
          &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<BlePlusPlugin>();
  auto plugin_ptr = plugin.get();
  plugin_ptr->registrar_ = registrar;

  // Dispatch to the platform thread: a message-only window is created on the
  // platform thread (the one that registers plugins). Any pool thread delivers
  // work with PostMessage; the window's WndProc runs on the platform's message
  // pump and executes the action.
  //
  // Why a message-only window and not RegisterTopLevelWindowProcDelegate: the
  // engine delegate NEVER delivered custom messages (registered with
  // RegisterWindowMessage), so scan events were lost. The message-only window
  // is the canonical Windows mechanism and does not depend on the engine. On
  // hot restart RegisterClass fails (the class already exists) and is ignored.
  {
    WNDCLASS wc{};
    wc.lpfnWndProc = &BlePlusPlugin::DispatchWndProc;
    wc.hInstance = ::GetModuleHandle(nullptr);
    wc.lpszClassName = L"ble_plus_platform_dispatch";
    ::RegisterClass(&wc);
    plugin_ptr->dispatch_message_ =
        ::RegisterWindowMessage(L"ble_plus_platform_dispatch");
    g_dispatch_message = plugin_ptr->dispatch_message_;
    plugin_ptr->platform_hwnd_ =
        ::CreateWindowEx(0, wc.lpszClassName, nullptr, 0, 0, 0, 0, 0,
                         HWND_MESSAGE, nullptr, wc.hInstance, nullptr);
  }

  method_channel->SetMethodCallHandler(
      [plugin_ptr](const auto &call, auto result) {
        plugin_ptr->HandleMethodCall(call, std::move(result));
      });

  // Stream handler for the scan channel: stores/releases the sink. Both
  // callbacks run on the platform thread (the engine delivers the listen
  // there).
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

  // Stream handler for the connection channel (connected/disconnected events).
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

  // Stream handler for the characteristic channel (GATT notifications).
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

  // Stream handler for the logs channel: if nobody subscribes, log_sink_ stays
  // nullptr and Log() emits nothing (zero overhead in production).
  auto log_handler = std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
      [plugin_ptr](const EncodableValue* args,
                   std::unique_ptr<flutter::EventSink<EncodableValue>>&& sink)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        plugin_ptr->log_sink_ = std::move(sink);
        return nullptr;
      },
      [plugin_ptr](const EncodableValue* args)
          -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
        plugin_ptr->log_sink_ = nullptr;
        return nullptr;
      });
  log_channel->SetStreamHandler(std::move(log_handler));

  registrar->AddPlugin(std::move(plugin));
}

BlePlusPlugin::BlePlusPlugin() : platform_thread_id_(GetCurrentThreadId()) {
  // Attempt to initialize an STA apartment for the platform thread.
  // RPC_E_CHANGED_MODE: the thread already had an apartment of another mode
  // (e.g. the engine's MTA). Not an error: we respect the existing apartment
  // and delivery of results is decided at runtime per thread
  // (RunOnPlatformThread). cppwinrt coroutines were not reliable on this STA
  // thread (see AGENTS.md), so operations run on std::thread(...).detach().
  try {
    winrt::init_apartment(winrt::apartment_type::single_threaded);
  } catch (const winrt::hresult_error&) {
  }
}

BlePlusPlugin::~BlePlusPlugin() {
  StopScan();
  if (platform_hwnd_ != nullptr) {
    // Destroy the dispatch message-only window (must be done on the thread that
    // created it; the destructor runs on the platform thread).
    ::DestroyWindow(platform_hwnd_);
    platform_hwnd_ = nullptr;
  }
}

// WndProc of the dispatch message-only window. Runs on the platform thread
// (the one that created it, via its message pump) and executes the task.
LRESULT CALLBACK BlePlusPlugin::DispatchWndProc(HWND hwnd, UINT message,
                                                WPARAM wparam, LPARAM lparam) {
  if (g_dispatch_message != 0 && message == g_dispatch_message) {
    auto* task = reinterpret_cast<PlatformTask*>(lparam);
    if (task != nullptr) {
      task->Run();
      delete task;
    }
    return 0;
  }
  return ::DefWindowProc(hwnd, message, wparam, lparam);
}

// Executes [action] on the platform thread. If we are already on it, it is
// called directly (no overhead); otherwise it is dispatched with PostMessage to
// the message-only window created on the platform thread.
//
// IMPROVEMENT (documented, not implemented): if PostMessage fails (e.g. the
// window was destroyed on a hot restart) the task is deleted and the result is
// lost. There is no fallback to queue on a pool thread, but in practice the
// window is created once and survives hot restarts.
template <typename F>
void BlePlusPlugin::RunOnPlatformThread(F&& action) {
  if (GetCurrentThreadId() == platform_thread_id_) {
    std::forward<F>(action)();
  } else if (platform_hwnd_ != nullptr && dispatch_message_ != 0) {
    auto* task =
        new PlatformTaskImpl<std::decay_t<F>>(std::forward<F>(action));
    if (!::PostMessage(platform_hwnd_, dispatch_message_, 0,
                       reinterpret_cast<LPARAM>(task))) {
      delete task;
    }
  }
}

std::shared_ptr<std::mutex> BlePlusPlugin::GetDeviceGattMutex(
    const std::string& device_id) {
  // Windows only allows ONE pending GATT operation per device; if two are
  // launched at once, one fails or hangs. Each device has its own mutex so
  // independent devices are not blocked by each other.
  std::lock_guard<std::mutex> lock(devices_mutex_);
  auto& p = device_gatt_mutex_[device_id];
  if (!p) {
    p = std::make_shared<std::mutex>();
  }
  return p;
}

void BlePlusPlugin::HandleMethodCall(
    const flutter::MethodCall<EncodableValue> &method_call,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {

  const auto& method = method_call.method_name();
  // All contract methods receive an argument map; if it is not a map
  // (e.g. null), an empty map is used.
  const auto* args_ptr = std::get_if<EncodableMap>(method_call.arguments());
  EncodableMap args = args_ptr ? *args_ptr : EncodableMap{};

  if (method == "getAdapterState") {
    GetAdapterState(std::move(result));
  } else if (method == "requestEnable") {
    RequestEnable(std::move(result));
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
    // Arguments are extracted safely: if any is missing or of the wrong type,
    // std::get throws std::bad_variant_access → INVALID_ARGS.
    try {
      auto did = std::get<std::string>(args[EncodableValue("deviceId")]);
      auto sid = std::get<std::string>(args[EncodableValue("serviceUuid")]);
      auto cid = std::get<std::string>(args[EncodableValue("characteristicUuid")]);
      ReadCharacteristic(did, sid, cid, std::move(result));
    } catch (...) {
      result->Error("INVALID_ARGS", "Invalid arguments for readCharacteristic");
    }
  } else if (method == "writeCharacteristic") {
    try {
      auto did = std::get<std::string>(args[EncodableValue("deviceId")]);
      auto sid = std::get<std::string>(args[EncodableValue("serviceUuid")]);
      auto cid = std::get<std::string>(args[EncodableValue("characteristicUuid")]);
      // The value arrives as a list of integers (bytes); converted to uint8_t.
      auto val_list = std::get<EncodableList>(args[EncodableValue("value")]);
      std::vector<uint8_t> value;
      for (const auto& v : val_list) {
        value.push_back(static_cast<uint8_t>(std::get<int32_t>(v)));
      }
      auto wr = std::get<bool>(args[EncodableValue("withResponse")]);
      WriteCharacteristic(did, sid, cid, value, wr, std::move(result));
    } catch (...) {
      result->Error("INVALID_ARGS", "Invalid arguments for writeCharacteristic");
    }
  } else if (method == "setNotification") {
    try {
      auto did = std::get<std::string>(args[EncodableValue("deviceId")]);
      auto sid = std::get<std::string>(args[EncodableValue("serviceUuid")]);
      auto cid = std::get<std::string>(args[EncodableValue("characteristicUuid")]);
      auto enable = std::get<bool>(args[EncodableValue("enable")]);
      SetNotification(did, sid, cid, enable, std::move(result));
    } catch (...) {
      result->Error("INVALID_ARGS", "Invalid arguments for setNotification");
    }
  } else if (method == "requestMtu") {
    // Windows auto-negotiates MTU (the real value can be read from
    // GattSession::MaxPduSize).
    result->Success(EncodableValue(517));
  } else if (method == "getConnectedDevices") {
    std::lock_guard<std::mutex> lock(mutex_);
    EncodableList ids;
    for (const auto& pair : devices_) {
      ids.push_back(EncodableValue(pair.first));
    }
    result->Success(EncodableValue(ids));
  } else if (method == "createBond") {
    // Windows handles pairing automatically during GATT operations.
    result->Success(EncodableValue(nullptr));
  } else if (method == "removeBond") {
    result->Error("UNSUPPORTED", "Windows does not support programmatic bond removal");
  } else if (method == "getBondState") {
    // Queries the pairing state via DeviceInformation::Pairing(). Done on the
    // platform thread because it is a short, synchronous call.
    auto it = args.find(EncodableValue("deviceId"));
    if (it != args.end()) {
      try {
        auto device_id = std::get<std::string>(it->second);
        std::lock_guard<std::mutex> lock(mutex_);
        auto dev_it = devices_.find(device_id);
        if (dev_it != devices_.end()) {
          auto info = dev_it->second.DeviceInformation();
          auto pairing = info.Pairing();
          result->Success(EncodableValue(pairing.IsPaired() ? 2 : 0)); // 2=bonded, 0=none
        } else {
          result->Success(EncodableValue(0));
        }
      } catch (...) {
        // If the pairing query fails, respond "not paired" (0) instead of
        // breaking the UI flow.
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
// ADAPTER
// ═══════════════════════════════════════════════════════════

void BlePlusPlugin::GetAdapterState(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  // The adapter query is async and runs on a detached thread so the platform
  // thread is not blocked. The result is delivered back with
  // RunOnPlatformThread.
  std::thread([this, result = std::move(result)]() mutable {
    int state = 0;  // unknown
    try {
      Log(kLogInfo, "adapter", "Querying BLE adapter state...");
      auto adapter_op = BluetoothAdapter::GetDefaultAsync();
      auto adapter = AwaitWithTimeout(adapter_op, std::chrono::seconds(2));
      if (adapter.has_value() && *adapter != nullptr) {
        if ((*adapter).IsLowEnergySupported()) {
          auto radio_op = (*adapter).GetRadioAsync();
          auto radio = AwaitWithTimeout(radio_op, std::chrono::seconds(2));
          if (radio.has_value() && *radio != nullptr &&
              (*radio).State() ==
                  winrt::Windows::Devices::Radios::RadioState::On) {
            state = 4;  // poweredOn
          } else {
            state = 6;  // poweredOff
          }
        } else {
          state = 1;  // unsupported
        }
      } else {
        state = 1;  // unsupported
      }
    } catch (winrt::hresult_error const& e) {
      // WinRT exceptions are not std::exception: they must be caught
      // separately.
      std::ostringstream oss;
      oss << "Error querying the adapter: 0x" << std::hex << std::uppercase
          << e.to_abi();
      Log(kLogError, "adapter", oss.str());
      state = 0;  // unknown
    } catch (const std::exception& e) {
      Log(kLogError, "adapter", std::string("std exception: ") + e.what());
      state = 0;  // unknown
    } catch (...) {
      Log(kLogError, "adapter", "Unknown exception");
      state = 0;  // unknown
    }

    int adapter_state = state;
    Log(kLogInfo, "adapter",
        "BLE adapter state = " + std::to_string(adapter_state));
    RunOnPlatformThread([result = std::move(result), adapter_state]() mutable {
      result->Success(EncodableValue(adapter_state));
    });
  }).detach();
}

void BlePlusPlugin::RequestEnable(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  // WinRT/UWP does not expose an API to turn the radio on programmatically
  // (Windows requires the user to enable it in Settings). Respond false so the
  // app knows and guides the user.
  std::thread([this, result = std::move(result)]() mutable {
    Log(kLogInfo, "adapter", "requestEnable: not supported, returning false");
    RunOnPlatformThread([result = std::move(result)]() mutable {
      result->Success(EncodableValue(false));
    });
  }).detach();
}

// ═══════════════════════════════════════════════════════════
// SCANNING
// ═══════════════════════════════════════════════════════════

void BlePlusPlugin::StartScan(const EncodableMap& args) {
  StopScan();  // Stop any existing scan (only one watcher at a time).

  watcher_ = BluetoothLEAdvertisementWatcher();
  // Active mode: besides the initial advertisement, scan responses are
  // requested, which is where the device name usually comes from.
  watcher_.ScanningMode(BluetoothLEScanningMode::Active);

  watcher_.Received([this](BluetoothLEAdvertisementWatcher const&,
                           BluetoothLEAdvertisementReceivedEventArgs const& eventArgs) {
    // This callback runs on WinRT thread pool threads. All access to plugin
    // state/sinks is done under mutex or deferred to the platform thread. Any
    // exception that escapes here terminates the process, so the whole body is
    // wrapped in try/catch.
    try {
    auto address = eventArgs.BluetoothAddress();
    // The MAC address is formatted in uppercase with ':' separators as a
    // stable device id for the whole session.
    std::ostringstream addr_stream;
    addr_stream << std::hex << std::setfill('0');
    for (int i = 5; i >= 0; i--) {
      addr_stream << std::setw(2) << ((address >> (i * 8)) & 0xFF);
      if (i > 0) addr_stream << ":";
    }
    auto device_id = addr_stream.str();
    std::transform(device_id.begin(), device_id.end(), device_id.begin(),
                   [](unsigned char c) { return static_cast<char>(::toupper(c)); });

    auto ad = eventArgs.Advertisement();
    std::string name;
    if (!ad.LocalName().empty()) {
      name = winrt::to_string(ad.LocalName());
      // The name sometimes arrives in the scan response (a separate event with
      // the same address); it is accumulated for later events. This explains
      // the "delay" when showing names: the device is listed first without a
      // name and is completed when the scan response arrives.
      std::lock_guard<std::mutex> lock(mutex_);
      device_names_[device_id] = name;
    } else {
      std::lock_guard<std::mutex> lock(mutex_);
      auto it = device_names_.find(device_id);
      if (it != device_names_.end()) {
        name = it->second;
      }
    }

    EncodableList service_uuids;
    for (const auto& uuid : ad.ServiceUuids()) {
      service_uuids.push_back(EncodableValue(GuidToString(uuid)));
    }

    // Manufacturer data: map companyId → byte list. Read with a DataReader over
    // the advertisement buffer.
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

    Log(kLogDebug, "scan",
        "Received " + device_id + " '" + name + "' rssi=" +
            std::to_string(eventArgs.RawSignalStrengthInDBm()));

    // WinRT callbacks can arrive on pool threads; they are always delivered on
    // the platform thread so the sinks are not corrupted.
    EncodableValue payload(result);
    RunOnPlatformThread([this, payload = std::move(payload)]() mutable {
      if (scan_sink_) {
        scan_sink_->Success(std::move(payload));
      }
    });
    } catch (...) {
      // Do not propagate callback exceptions to the thread's message pump.
      Log(kLogError, "scan", "Exception processing advertisement");
    }
  });

  // IMPROVEMENT (documented): the watcher starts
  // here, on the platform thread, right when Dart calls startScan. If the Dart
  // side is not subscribed to the EventChannel yet (the subscription happens
  // after the method call), the first advertisements are lost → the device list
  // appears incomplete. Proposals: native buffer of the last N, or start the
  // watcher only when the channel's onListen arrives.
  watcher_.Start();
  Log(kLogInfo, "scan", "Watcher started");
}

void BlePlusPlugin::StopScan() {
  if (watcher_ != nullptr) {
    try {
      watcher_.Stop();
    } catch (...) {
    }
    watcher_ = nullptr;
    Log(kLogInfo, "scan", "Watcher stopped");
  }
}

// ═══════════════════════════════════════════════════════════
// CONNECTION
// ═══════════════════════════════════════════════════════════

void BlePlusPlugin::Connect(
    const std::string& device_id,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  // All the heavy work (connect + wait) goes on a detached thread so the UI is
  // not blocked. The result/event is delivered with RunOnPlatformThread.
  std::thread([this, device_id, result = std::move(result)]() mutable {
    Log(kLogInfo, "connect", "Connecting to " + device_id);
    try {
      // Parse MAC address to uint64: the address arrives as
      // "AA:BB:CC:DD:EE:FF" and WinRT wants it as an integer.
      uint64_t address = 0;
      std::string addr = device_id;
      addr.erase(std::remove(addr.begin(), addr.end(), ':'), addr.end());
      try {
        address = std::stoull(addr, nullptr, 16);
      } catch (...) {
        SendError(std::move(result),
                  MakeError("INVALID_ARGS", "connect:parseAddress",
                            "Invalid device address"));
        return;
      }

      // Gets the BluetoothLEDevice object. NOTE: this does NOT establish the
      // connection (Windows connects lazily on the first GATT operation); the
      // real link is forced below with GattSession.
      auto op = BluetoothLEDevice::FromBluetoothAddressAsync(address);
      auto device = AwaitWithTimeout(op, std::chrono::seconds(15));
      if (!device.has_value()) {
        auto err = MakeError("TIMEOUT", "connect:fromAddress",
                             "Connection timed out");
        err.device_id = device_id;
        SendError(std::move(result), err);
        return;
      }
      if (*device == nullptr) {
        auto err = MakeError("NOT_FOUND", "connect:fromAddress",
                             "Device not found");
        err.device_id = device_id;
        SendError(std::move(result), err);
        return;
      }

      {
        std::lock_guard<std::mutex> lock(mutex_);
        devices_.insert_or_assign(device_id, *device);
      }

      // Establish the real GATT connection: GattSession + MaintainConnection
      // force the link; the object is kept to keep it alive.
      // IMPROVEMENT (documented): the silent catch below used to hide failures
      // at this stage. With the current logging they are visible in the
      // "ble_plus/log" channel.
      try {
        auto session_op = GattSession::FromDeviceIdAsync(
            BluetoothDeviceId::FromId((*device).DeviceId()));
        auto session = AwaitWithTimeout(session_op, std::chrono::seconds(10));
        if (session.has_value() && *session != nullptr) {
          (*session).MaintainConnection(true);
          std::lock_guard<std::mutex> lock(mutex_);
          device_sessions_.insert_or_assign(device_id, *session);
          Log(kLogDebug, "connect",
              "GattSession created and MaintainConnection=true for " + device_id);
        } else {
          Log(kLogWarning, "connect",
              "Could not create GattSession for " + device_id +
                  " (will continue without a maintained link)");
        }
      } catch (winrt::hresult_error const& e) {
        std::ostringstream oss;
        oss << "GattSession failed: 0x" << std::hex << std::uppercase << e.to_abi();
        Log(kLogWarning, "connect", oss.str());
      } catch (...) {
        Log(kLogWarning, "connect", "GattSession failed (unknown exception)");
      }

      // Wait until Windows reports the connection established (up to ~10s).
      // IMPROVEMENT (documented): 1) this polling could be replaced by the
      // ConnectionStatusChanged event; 2) the native timeout is fixed (10-15s)
      // and does not use the timeoutMs that the Dart API already sends in
      // ConnectionSettings.
      bool connected = false;
      for (int i = 0; i < 50; ++i) {
        if ((*device).ConnectionStatus() == BluetoothConnectionStatus::Connected) {
          connected = true;
          break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(200));
      }
      if (!connected) {
        auto err = MakeError("CONNECTION_FAILED", "connect:statusPolling",
                             "Device unreachable");
        err.device_id = device_id;
        SendError(std::move(result), err);
        return;
      }

      auto did = device_id;
      Log(kLogInfo, "connect", "Connected to " + did);
      RunOnPlatformThread([this, did, result = std::move(result)]() mutable {
        if (connection_sink_) {
          EncodableMap event;
          event[EncodableValue("deviceId")] = EncodableValue(did);
          event[EncodableValue("state")] = EncodableValue(2);  // connected
          connection_sink_->Success(EncodableValue(event));
        }
        result->Success(EncodableValue(nullptr));
      });
    } catch (winrt::hresult_error const& e) {
      auto err = MakeError("CONNECTION_FAILED", "connect:winrt",
                           winrt::to_string(e.message()));
      err.device_id = device_id;
      err.hresult = e.to_abi();
      Log(kLogError, "connect", winrt::to_string(e.message()));
      SendError(std::move(result), err);
    } catch (const std::exception& e) {
      auto err = MakeError("CONNECTION_FAILED", "connect:std",
                           std::string(e.what()));
      err.device_id = device_id;
      Log(kLogError, "connect", std::string(e.what()));
      SendError(std::move(result), err);
    } catch (...) {
      auto err = MakeError("CONNECTION_FAILED", "connect:unknown",
                           "Unknown native error");
      err.device_id = device_id;
      Log(kLogError, "connect", "Unknown exception in connect");
      SendError(std::move(result), err);
    }
  }).detach();
}

void BlePlusPlugin::Disconnect(const std::string& device_id) {
  Log(kLogInfo, "connect", "Disconnecting " + device_id);
  {
    std::lock_guard<std::mutex> lock(mutex_);
    devices_.erase(device_id);
    device_services_.erase(device_id);
    device_names_.erase(device_id);
    auto sit = device_sessions_.find(device_id);
    if (sit != device_sessions_.end()) {
      try {
        // Release the maintained link; without this the connection would stay
        // alive on the stack even though the app closed it (ghost connection).
        sit->second.MaintainConnection(false);
      } catch (...) {
      }
      device_sessions_.erase(sit);
    }
    // Clear the device's characteristic cache.
    std::string prefix = device_id + "|";
    for (auto it = device_characteristics_.begin();
         it != device_characteristics_.end();) {
      if (it->first.compare(0, prefix.size(), prefix) == 0) {
        it = device_characteristics_.erase(it);
      } else {
        ++it;
      }
    }
  }
  {
    std::lock_guard<std::mutex> lock(devices_mutex_);
    device_gatt_mutex_.erase(device_id);
  }

  // Disconnect is invoked from the platform thread (via HandleMethodCall), so
  // accessing the sink here is safe. Note: this is the ONLY point that emits
  // "disconnected"; if the device drops by itself, the app never finds out.
  if (connection_sink_) {
    EncodableMap event;
    event[EncodableValue("deviceId")] = EncodableValue(device_id);
    event[EncodableValue("state")] = EncodableValue(0);  // disconnected
    connection_sink_->Success(EncodableValue(event));
  }
}

// ═══════════════════════════════════════════════════════════
// GATT
// ═══════════════════════════════════════════════════════════

void BlePlusPlugin::DiscoverServices(
    const std::string& device_id,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  std::thread([this, device_id, result = std::move(result)]() mutable {
    try {
      // Windows only allows one pending GATT operation per device.
      // Reads/writes/discover of the same device are serialized.
      auto gatt_lock = GetDeviceGattMutex(device_id);
      std::lock_guard<std::mutex> lock(*gatt_lock);

      BluetoothLEDevice device{nullptr};
      {
        std::lock_guard<std::mutex> lk(mutex_);
        auto it = devices_.find(device_id);
        if (it == devices_.end()) {
          Log(kLogWarning, "discover",
              device_id + ": device not found in devices_ (NOT_CONNECTED)");
          SendError(std::move(result),
                    MakeError("NOT_CONNECTED", "discoverServices:device",
                              "Not connected"));
          return;
        }
        device = it->second;
      }
      Log(kLogDebug, "discover", device_id + ": device found, starting discover");

      // ==========================================================================
      // IMPROVEMENT IMPLEMENTED: the peripheral
      // aborts the CRT on GetGattServicesAsync(Uncached) — enumerating all
      // services over the air includes the Generic Attribute Service 0x1801 /
      // Service Changed, the same mechanism behind the historical
      // FindCharacteristic abort. So it is queried FIRST with
      // BluetoothCacheMode::Cached (the OS cache is populated during
      // connect/GattSession) and only if the cache is empty a SINGLE Uncached
      // attempt is made as fallback.
      // ==========================================================================
      // Retries GetGattServicesAsync with the given mode up to 3 times if
      // Windows reports Unreachable (the link may still be associating).
      auto fetch_with_mode = [this, &device](BluetoothCacheMode mode)
          -> std::optional<GattDeviceServicesResult> {
        std::string mode_str =
            mode == BluetoothCacheMode::Cached ? "Cached" : "Uncached";
        for (int attempt = 0; attempt < 3; ++attempt) {
          Log(kLogDebug, "discover",
              "attempt " + std::to_string(attempt + 1) + " [" + mode_str +
                  "]: creating GetGattServicesAsync...");
          auto op = device.GetGattServicesAsync(mode);
          Log(kLogDebug, "discover",
              "attempt " + std::to_string(attempt + 1) + " [" + mode_str +
                  "]: operation created, waiting for result (10s timeout)...");
          auto r = AwaitWithTimeout(op, std::chrono::seconds(10));
          if (!r.has_value()) {
            Log(kLogWarning, "discover",
                "attempt " + std::to_string(attempt + 1) + " [" + mode_str +
                    "]: AwaitWithTimeout returned timeout/nullopt");
            return std::nullopt;
          }
          Log(kLogDebug, "discover",
              "attempt " + std::to_string(attempt + 1) + " [" + mode_str +
                  "]: status=" + std::to_string(static_cast<int32_t>(r->Status())) +
                  " protocolError=" +
                  (r->ProtocolError()
                       ? std::to_string(
                             static_cast<int32_t>(r->ProtocolError().Value()))
                       : "none"));
          if (r->Status() != GattCommunicationStatus::Unreachable) {
            return r;
          }
          std::this_thread::sleep_for(std::chrono::milliseconds(500));
        }
        return std::nullopt;
      };

      // 1) Cached: avoids the full over-the-air GATT query (no abort).
      std::optional<GattDeviceServicesResult> services_result =
          fetch_with_mode(BluetoothCacheMode::Cached);
      // 2) If the cache is empty (Success with 0 services), fall back with a
      //    single Uncached attempt for devices that do not have a cache yet.
      if (services_result.has_value() &&
          services_result->Status() == GattCommunicationStatus::Success &&
          services_result->Services().Size() == 0) {
        Log(kLogWarning, "discover",
            device_id +
                ": Cached returned 0 services, falling back to Uncached (1 attempt)");
        services_result = fetch_with_mode(BluetoothCacheMode::Uncached);
      }
      if (!services_result.has_value()) {
        Log(kLogError, "discover", device_id + ": service discovery TIMEOUT");
        auto err = MakeError("TIMEOUT", "discoverServices:timeout",
                             "Service discovery timed out");
        err.device_id = device_id;
        SendError(std::move(result), err);
        return;
      }
      if (services_result->Status() != GattCommunicationStatus::Success) {
        auto err = MakeError("GATT_ERROR", "discoverServices:status",
                             "Failed to get services");
        err.device_id = device_id;
        err.gatt_status = static_cast<int32_t>(services_result->Status());
        // ProtocolError is IReference<uint8_t> (nullable): only reported if
        // the device returned a protocol code.
        if (auto pe = services_result->ProtocolError()) {
          err.protocol_error = static_cast<int32_t>(pe.Value());
        }
        Log(kLogError, "discover",
            device_id + ": GetGattServicesAsync status=" +
                std::to_string(static_cast<int32_t>(services_result->Status())) +
                " (GATT_ERROR)");
        SendError(std::move(result), err);
        return;
      }

      Log(kLogDebug, "discover",
          device_id + ": GetGattServicesAsync OK, enumerating services...");
      EncodableList services_list;
      std::vector<GattDeviceService> service_handles;
      std::vector<std::pair<std::string, GattCharacteristic>> cached_chars;

      for (const auto& service : services_result->Services()) {
        service_handles.push_back(service);
        auto service_uuid = GuidToString(service.Uuid());

        Log(kLogDebug, "discover",
            device_id + ": service " + service_uuid +
                " → creating GetCharacteristicsAsync...");
        auto chars_op = service.GetCharacteristicsAsync();
        Log(kLogDebug, "discover",
            device_id + ": service " + service_uuid +
                " → operation created, waiting (10s timeout)...");
        auto chars_result = AwaitWithTimeout(chars_op, std::chrono::seconds(10));
        EncodableList chars_list;
        if (chars_result.has_value() &&
            chars_result->Status() == GattCommunicationStatus::Success) {
          Log(kLogDebug, "discover",
              device_id + ": service " + service_uuid + " → " +
                  std::to_string(chars_result->Characteristics().Size()) +
                  " characteristics");
          for (const auto& ch : chars_result->Characteristics()) {
            auto props = static_cast<int32_t>(ch.CharacteristicProperties());
            // Diagnostics: each UUID is logged to know where each
            // characteristic lives (e.g. the Battery 2A19 and its service).
            Log(kLogDebug, "discover",
                device_id + ":   char " + GuidToString(ch.Uuid()) +
                    " props=" + std::to_string(props));
            EncodableMap char_map;
            char_map[EncodableValue("uuid")] = EncodableValue(GuidToString(ch.Uuid()));
            char_map[EncodableValue("serviceUuid")] = EncodableValue(service_uuid);
            char_map[EncodableValue("properties")] = EncodableValue(props);
            char_map[EncodableValue("descriptors")] = EncodableValue(EncodableList{});
            chars_list.push_back(EncodableValue(char_map));
            // Cache the characteristic to avoid re-querying GATT by UUID.
            // IMPROVEMENT (documented): if GetCharacteristicsAsync of a
            // service fails here, its characteristics are not cached and a
            // later read/write reports them "not found" or re-queries.
            cached_chars.emplace_back(
                device_id + "|" + service_uuid + "|" + GuidToString(ch.Uuid()),
                ch);
          }
        } else {
          Log(kLogWarning, "discover",
              device_id + ": service " + service_uuid +
                  " → GetCharacteristicsAsync without result (status=" +
                  (chars_result.has_value()
                       ? std::to_string(static_cast<int32_t>(chars_result->Status()))
                       : "timeout") +
                  ")");
        }

        EncodableMap service_map;
        service_map[EncodableValue("uuid")] = EncodableValue(service_uuid);
        service_map[EncodableValue("isPrimary")] = EncodableValue(true);
        service_map[EncodableValue("characteristics")] = EncodableValue(chars_list);
        service_map[EncodableValue("includedServices")] = EncodableValue(EncodableList{});
        services_list.push_back(EncodableValue(service_map));
      }

      {
        std::lock_guard<std::mutex> lk(mutex_);
        device_services_[device_id] = std::move(service_handles);
        for (auto& kv : cached_chars) {
          device_characteristics_.insert_or_assign(std::move(kv.first),
                                                   std::move(kv.second));
        }
      }

      Log(kLogInfo, "discover",
          device_id + ": " + std::to_string(services_list.size()) +
              " services discovered");
      RunOnPlatformThread([result = std::move(result),
                           services_list = std::move(services_list)]() mutable {
        result->Success(EncodableValue(services_list));
      });
    } catch (winrt::hresult_error const& e) {
      auto err = MakeError("GATT_ERROR", "discoverServices:winrt",
                           winrt::to_string(e.message()));
      err.device_id = device_id;
      err.hresult = e.to_abi();
      Log(kLogError, "discover", winrt::to_string(e.message()));
      SendError(std::move(result), err);
    } catch (const std::exception& e) {
      auto err = MakeError("GATT_ERROR", "discoverServices:std",
                           std::string(e.what()));
      err.device_id = device_id;
      Log(kLogError, "discover", std::string(e.what()));
      SendError(std::move(result), err);
    } catch (...) {
      auto err = MakeError("GATT_ERROR", "discoverServices:unknown",
                           "Unknown native error");
      err.device_id = device_id;
      Log(kLogError, "discover", "Unknown exception in discoverServices");
      SendError(std::move(result), err);
    }
  }).detach();
}

void BlePlusPlugin::ReadCharacteristic(
    const std::string& device_id,
    const std::string& service_uuid,
    const std::string& char_uuid,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  std::thread([this, device_id, service_uuid, char_uuid,
               result = std::move(result)]() mutable {
    try {
      // Serializes the device's GATT operations (one at a time).
      auto gatt_lock = GetDeviceGattMutex(device_id);
      std::lock_guard<std::mutex> lock(*gatt_lock);

      auto ch = FindCharacteristic(device_id, service_uuid, char_uuid);
      if (ch == nullptr) {
        auto err = MakeError("NOT_FOUND", "readCharacteristic:cache",
                             "Characteristic not found");
        err.device_id = device_id;
        SendError(std::move(result), err);
        return;
      }

      auto op = ch.ReadValueAsync();
      auto read_result = AwaitWithTimeout(op, std::chrono::seconds(10));

      // IMPROVEMENT (16-Aug-2026, diagnostic): the peripheral responds with
      // protocolError=7 (Invalid Offset) to an Uncached read, although a BLE
      // scanner reads it. It is retried ONCE with BluetoothCacheMode::Cached
      // (the cache is populated by discover) to check whether the over-the-air
      // read is the problem. If the retry yields the value, it is adopted as a
      // fallback; otherwise the original error is reported.
      if (read_result.has_value() &&
          read_result->Status() != GattCommunicationStatus::Success) {
        auto first_protocol = read_result->ProtocolError();
        Log(kLogWarning, "gatt",
            "Read " + char_uuid + " status=" +
                std::to_string(static_cast<int32_t>(read_result->Status())) +
                " protocolError=" +
                (first_protocol
                     ? std::to_string(static_cast<int32_t>(first_protocol.Value()))
                     : "none") +
                " → retrying with ReadValueAsync(Cached)...");
        auto op_cached = ch.ReadValueAsync(BluetoothCacheMode::Cached);
        read_result = AwaitWithTimeout(op_cached, std::chrono::seconds(10));
      }

      if (!read_result.has_value()) {
        auto err = MakeError("TIMEOUT", "readCharacteristic:timeout",
                             "Read timed out");
        err.device_id = device_id;
        SendError(std::move(result), err);
        return;
      }
      if (read_result->Status() != GattCommunicationStatus::Success) {
        // A non-Success status usually carries a device protocolError (e.g.
        // protocolError=7 on the Battery 2A19 read of the test device — the
        // firmware rejects it, it is not a plugin bug).
        auto err = MakeError("GATT_ERROR", "readCharacteristic:status",
                             "Read failed");
        err.device_id = device_id;
        err.gatt_status = static_cast<int32_t>(read_result->Status());
        // ProtocolError is IReference<uint8_t> (nullable): only reported if
        // the device returned a protocol code.
        auto protocol = read_result->ProtocolError();
        if (protocol) {
          err.protocol_error = static_cast<int32_t>(protocol.Value());
        }
        Log(kLogWarning, "gatt",
            "Read failed: status=" +
                std::to_string(static_cast<int32_t>(read_result->Status())) +
                " protocolError=" +
                (protocol ? std::to_string(static_cast<int32_t>(protocol.Value()))
                          : "none"));
        SendError(std::move(result), err);
        return;
      }

      auto reader = DataReader::FromBuffer(read_result->Value());
      std::vector<uint8_t> bytes(reader.UnconsumedBufferLength());
      if (!bytes.empty()) reader.ReadBytes(bytes);

      EncodableList value;
      for (auto b : bytes)
        value.push_back(EncodableValue(static_cast<int32_t>(b)));

      Log(kLogDebug, "gatt",
          "Read OK " + char_uuid + " = " + std::to_string(bytes.size()) + " bytes");
      RunOnPlatformThread([result = std::move(result),
                           value = std::move(value)]() mutable {
        result->Success(EncodableValue(value));
      });
    } catch (winrt::hresult_error const& e) {
      auto err = MakeError("GATT_ERROR", "readCharacteristic:winrt",
                           winrt::to_string(e.message()));
      err.device_id = device_id;
      err.hresult = e.to_abi();
      Log(kLogError, "gatt", winrt::to_string(e.message()));
      SendError(std::move(result), err);
    } catch (const std::exception& e) {
      auto err = MakeError("GATT_ERROR", "readCharacteristic:std",
                           std::string(e.what()));
      err.device_id = device_id;
      Log(kLogError, "gatt", std::string(e.what()));
      SendError(std::move(result), err);
    } catch (...) {
      auto err = MakeError("GATT_ERROR", "readCharacteristic:unknown",
                           "Unknown native error");
      err.device_id = device_id;
      Log(kLogError, "gatt", "Unknown exception in readCharacteristic");
      SendError(std::move(result), err);
    }
  }).detach();
}

void BlePlusPlugin::WriteCharacteristic(
    const std::string& device_id,
    const std::string& service_uuid,
    const std::string& char_uuid,
    const std::vector<uint8_t>& value,
    bool with_response,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  std::thread([this, device_id, service_uuid, char_uuid, value, with_response,
               result = std::move(result)]() mutable {
    try {
      auto gatt_lock = GetDeviceGattMutex(device_id);
      std::lock_guard<std::mutex> lock(*gatt_lock);

      auto ch = FindCharacteristic(device_id, service_uuid, char_uuid);
      if (ch == nullptr) {
        auto err = MakeError("NOT_FOUND", "writeCharacteristic:cache",
                             "Characteristic not found");
        err.device_id = device_id;
        SendError(std::move(result), err);
        return;
      }

      // The bytes are packed into a DataWriter → IBuffer for WinRT.
      auto writer = DataWriter();
      writer.WriteBytes(value);
      auto buffer = writer.DetachBuffer();

      // WithResponse = confirmed write (waits for the device's ACK);
      // WithoutResponse = fire-and-forget (GATT write without response).
      auto option = with_response
          ? GattWriteOption::WriteWithResponse
          : GattWriteOption::WriteWithoutResponse;

      auto op = ch.WriteValueAsync(buffer, option);
      auto write_result = AwaitWithTimeout(op, std::chrono::seconds(10));
      if (!write_result.has_value()) {
        auto err = MakeError("TIMEOUT", "writeCharacteristic:timeout",
                             "Write timed out");
        err.device_id = device_id;
        SendError(std::move(result), err);
        return;
      }
      if (*write_result != GattCommunicationStatus::Success) {
        auto err = MakeError("GATT_ERROR", "writeCharacteristic:status",
                             "Write failed");
        err.device_id = device_id;
        err.gatt_status = static_cast<int32_t>(*write_result);
        Log(kLogWarning, "gatt",
            "Write failed: status=" +
                std::to_string(static_cast<int32_t>(*write_result)));
        SendError(std::move(result), err);
        return;
      }

      Log(kLogDebug, "gatt",
          "Write OK " + char_uuid + " = " + std::to_string(value.size()) +
              " bytes (withResponse=" + (with_response ? "true" : "false") + ")");
      RunOnPlatformThread([result = std::move(result)]() mutable {
        result->Success(EncodableValue(nullptr));
      });
    } catch (winrt::hresult_error const& e) {
      auto err = MakeError("GATT_ERROR", "writeCharacteristic:winrt",
                           winrt::to_string(e.message()));
      err.device_id = device_id;
      err.hresult = e.to_abi();
      Log(kLogError, "gatt", winrt::to_string(e.message()));
      SendError(std::move(result), err);
    } catch (const std::exception& e) {
      auto err = MakeError("GATT_ERROR", "writeCharacteristic:std",
                           std::string(e.what()));
      err.device_id = device_id;
      Log(kLogError, "gatt", std::string(e.what()));
      SendError(std::move(result), err);
    } catch (...) {
      auto err = MakeError("GATT_ERROR", "writeCharacteristic:unknown",
                           "Unknown native error");
      err.device_id = device_id;
      Log(kLogError, "gatt", "Unknown exception in writeCharacteristic");
      SendError(std::move(result), err);
    }
  }).detach();
}

void BlePlusPlugin::SetNotification(
    const std::string& device_id,
    const std::string& service_uuid,
    const std::string& char_uuid,
    bool enable,
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result) {
  std::thread([this, device_id, service_uuid, char_uuid, enable,
               result = std::move(result)]() mutable {
    try {
      auto gatt_lock = GetDeviceGattMutex(device_id);
      std::lock_guard<std::mutex> lock(*gatt_lock);

      auto ch = FindCharacteristic(device_id, service_uuid, char_uuid);
      if (ch == nullptr) {
        auto err = MakeError("NOT_FOUND", "setNotification:cache",
                             "Characteristic not found");
        err.device_id = device_id;
        SendError(std::move(result), err);
        return;
      }

      // Service Changed (2A05) is managed by the OS stack: it is the
      // characteristic the PERIPHERAL uses to indicate changes in its service
      // table, and Windows handles it internally to keep its cache. Writing
      // its CCCD from the app is non-standard usage that, in real testing,
      // hung the process exactly at this call. A clear error is returned
      // WITHOUT touching the descriptor.
      if (char_uuid.rfind("00002a05", 0) == 0) {
        auto err = MakeError("GATT_ERROR", "setNotification:serviceChanged",
                             "Service Changed (2A05) is managed by the OS; "
                             "manual subscription from the app is not supported");
        err.device_id = device_id;
        Log(kLogWarning, "gatt",
            "SetNotification ignored for Service Changed (2A05) of " + device_id);
        SendError(std::move(result), err);
        return;
      }

      // Subscribe is implemented by writing the Client Characteristic
      // Configuration Descriptor (CCCD): Notify to enable, None to disable.
      auto cccd_value = enable
          ? GattClientCharacteristicConfigurationDescriptorValue::Notify
          : GattClientCharacteristicConfigurationDescriptorValue::None;

      auto op = ch.WriteClientCharacteristicConfigurationDescriptorAsync(cccd_value);
      auto status = AwaitWithTimeout(op, std::chrono::seconds(10));
      if (!status.has_value()) {
        auto err = MakeError("TIMEOUT", "setNotification:timeout",
                             "Failed to set notification (timeout)");
        err.device_id = device_id;
        SendError(std::move(result), err);
        return;
      }
      Log(kLogDebug, "gatt",
          "SetNotification " + char_uuid + " CCCD status=" +
              std::to_string(static_cast<int32_t>(*status)));
      if (*status != GattCommunicationStatus::Success) {
        auto err = MakeError("GATT_ERROR", "setNotification:cccd",
                             "Failed to set notification");
        err.device_id = device_id;
        err.gatt_status = static_cast<int32_t>(*status);
        SendError(std::move(result), err);
        return;
      }

      if (enable) {
        // The callback is only registered when enabling; on disable the stack
        // simply stops emitting (the handler is overwritten on the next
        // enable).
        auto did = device_id;
        auto sid = service_uuid;
        auto cid = char_uuid;
        ch.ValueChanged([this, did, sid, cid](
            GattCharacteristic const&, GattValueChangedEventArgs const& args) {
          try {
          auto reader = DataReader::FromBuffer(args.CharacteristicValue());
          std::vector<uint8_t> bytes(reader.UnconsumedBufferLength());
          if (!bytes.empty()) reader.ReadBytes(bytes);

          EncodableList value;
          for (auto b : bytes)
            value.push_back(EncodableValue(static_cast<int32_t>(b)));

          EncodableMap event;
          event[EncodableValue("deviceId")] = EncodableValue(did);
          event[EncodableValue("serviceUuid")] = EncodableValue(sid);
          event[EncodableValue("characteristicUuid")] = EncodableValue(cid);
          event[EncodableValue("value")] = EncodableValue(value);

          // The WinRT callback can arrive on pool threads; it is delivered on
          // the platform thread so the sink is not corrupted.
          RunOnPlatformThread([this, event = std::move(event)]() mutable {
            if (char_sink_) {
              char_sink_->Success(EncodableValue(event));
            }
          });
          } catch (...) {
            // Do not propagate notification callback exceptions.
            Log(kLogError, "gatt", "Exception in ValueChanged callback");
          }
        });
      }

      RunOnPlatformThread([result = std::move(result)]() mutable {
        result->Success(EncodableValue(nullptr));
      });
    } catch (winrt::hresult_error const& e) {
      auto err = MakeError("GATT_ERROR", "setNotification:winrt",
                           winrt::to_string(e.message()));
      err.device_id = device_id;
      err.hresult = e.to_abi();
      Log(kLogError, "gatt", winrt::to_string(e.message()));
      SendError(std::move(result), err);
    } catch (const std::exception& e) {
      auto err = MakeError("GATT_ERROR", "setNotification:std",
                           std::string(e.what()));
      err.device_id = device_id;
      Log(kLogError, "gatt", std::string(e.what()));
      SendError(std::move(result), err);
    } catch (...) {
      auto err = MakeError("GATT_ERROR", "setNotification:unknown",
                           "Unknown native error");
      err.device_id = device_id;
      Log(kLogError, "gatt", "Unknown exception in setNotification");
      SendError(std::move(result), err);
    }
  }).detach();
}

// ═══════════════════════════════════════════════════════════
// HELPERS
// ═══════════════════════════════════════════════════════════

GattCharacteristic BlePlusPlugin::FindCharacteristic(
    const std::string& device_id,
    const std::string& service_uuid,
    const std::string& char_uuid) {
  // Uses the cache populated in DiscoverServices. Re-querying the GATT stack
  // by UUID (GetGattServicesForUuidAsync/GetCharacteristicsForUuidAsync)
  // caused abort() in ucrtbased.dll when accessing the Generic Attribute
  // Service (0x1801) / Service Changed. This cache is the mitigation for that
  // crash.
  std::lock_guard<std::mutex> lock(mutex_);
  auto it = device_characteristics_.find(
      device_id + "|" + service_uuid + "|" + char_uuid);
  if (it == device_characteristics_.end()) {
    Log(kLogDebug, "gatt", "FindCharacteristic: cache MISS " + char_uuid);
    return nullptr;
  }
  Log(kLogDebug, "gatt", "FindCharacteristic: cache HIT " + char_uuid);
  return it->second;
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
  // Parse a UUID string like "0000180d-0000-1000-8000-00805f9b34fb".
  // (Currently not used in the central flow; kept for utilities.)
  winrt::guid g;
  unsigned int d1, d2, d3;
  unsigned int d4[8];
  sscanf_s(s.c_str(), "%08x-%04x-%04x-%02x%02x-%02x%02x%02x%02x%02x%02x",
           &d1, &d2, &d3,
           &d4[0], &d4[1], &d4[2], &d4[3],
           &d4[4], &d4[5], &d4[6], &d4[7]);
  g.Data1 = d1;
  g.Data2 = static_cast<uint16_t>(d2);
  g.Data3 = static_cast<uint16_t>(d3);
  for (int i = 0; i < 8; i++) g.Data4[i] = static_cast<uint8_t>(d4[i]);
  return g;
}

void BlePlusPlugin::SendError(
    std::unique_ptr<flutter::MethodResult<EncodableValue>> result,
    const ErrorDetails& details) {
  // Builds the third argument of result->Error(...): a details map that
  // mapPlatformException (lib/src/errors/error_mapper.dart) parses to fill
  // platformCode/platformMessage of the BleError. "Empty" fields (hresult=0,
  // status<0, empty deviceId) are omitted to keep the map clean.
  EncodableMap map;
  map[EncodableValue("stage")] = EncodableValue(details.stage);
  map[EncodableValue("message")] = EncodableValue(details.message);
  if (!details.device_id.empty()) {
    map[EncodableValue("deviceId")] = EncodableValue(details.device_id);
  }
  if (details.hresult != 0) {
    std::ostringstream hr;
    hr << "0x" << std::hex << std::uppercase << details.hresult;
    map[EncodableValue("hresult")] = EncodableValue(hr.str());
  }
  if (details.gatt_status >= 0) {
    map[EncodableValue("gattStatus")] = EncodableValue(details.gatt_status);
  }
  if (details.protocol_error >= 0) {
    map[EncodableValue("protocolError")] = EncodableValue(details.protocol_error);
  }

  auto code = details.code;
  auto message = details.message;
  RunOnPlatformThread([result = std::move(result), code = std::move(code),
                       message = std::move(message),
                       map = std::move(map)]() mutable {
    // MethodResult::Error takes the details by const ref (T&); the temporary
    // is encoded synchronously within the call, so it is safe.
    result->Error(code, message, EncodableValue(map));
  });
}

void BlePlusPlugin::Log(int level, const std::string& tag,
                        const std::string& message) {
  // Safe from any thread: the map is built here (pool thread) and the send to
  // the sink runs on the platform thread. If nobody is subscribed
  // (log_sink_ == nullptr) nothing is emitted.
  EncodableMap entry;
  entry[EncodableValue("level")] = EncodableValue(level);
  entry[EncodableValue("tag")] = EncodableValue(tag);
  entry[EncodableValue("message")] = EncodableValue(message);
  EncodableValue payload(entry);
  RunOnPlatformThread([this, payload = std::move(payload)]() mutable {
    if (log_sink_) {
      log_sink_->Success(std::move(payload));
    }
  });
}

}  // namespace ble_plus
