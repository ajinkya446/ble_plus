# ble_plus — Complete Architecture & Implementation Design

> **Date:** August 2, 2026  
> **Status:** Design Document v1.0  
> **Author:** Senior Flutter + Native Mobile Engineer

---

## 1. Executive Summary

### Recommendation: Start a New Plugin (Do NOT Fork)

**Feasibility: YES** — this plugin is entirely feasible. Every major feature requested is supported by at least Android + iOS native APIs. The approach should be:

| Decision | Recommendation | Rationale |
|----------|---------------|-----------|
| Fork flutter_blue_plus? | **No — start fresh** | flutter_blue_plus has deep architectural coupling (global singletons, tight method channel binding, no peripheral support architecture). Refactoring would take longer than building clean. |
| Same API style? | **Partially** — keep familiar patterns for Central role (scan/connect/discover/read/write/notify) but redesign internals | Developers migrating from flutter_blue_plus should recognize the workflow, but we fix stream safety, error handling, and add peripheral separation |
| One plugin or federated set? | **Federated set of packages** | `ble_plus` (app-facing), `ble_plus_platform_interface`, `ble_plus_android`, `ble_plus_ios`, `ble_plus_macos`, `ble_plus_windows`, `ble_plus_linux`, `ble_plus_web` |
| MVP vs roadmap? | Central + Peripheral on Android/iOS = MVP. L2CAP, Windows, background = Phase 2-3 | Ship reliable core first |

### Why Not Fork

1. flutter_blue_plus uses `FlutterBluePlus` as a global singleton with hidden state
2. No architecture for peripheral role — would require rewriting 60%+ of native code
3. Stream handling has known issues with late listeners and dangling subscriptions
4. Method channel design is monolithic — a single channel handles everything
5. No separation between central/peripheral concerns at the platform interface level
6. Starting fresh with your existing scaffold gives you clean package boundaries from day 1

---

## 2. Feature Matrix

| Feature | Android | iOS | macOS | Linux | Web | Windows | Effort | Phase |
|---------|---------|-----|-------|-------|-----|---------|--------|-------|
| **Central: Scan** | ✅ Full | ✅ Full | ✅ Full | ✅ BlueZ | ⚠️ Limited | ✅ WinRT | Low | MVP |
| **Central: Connect** | ✅ Full | ✅ Full | ✅ Full | ✅ BlueZ | ⚠️ Limited | ✅ WinRT | Low | MVP |
| **Central: Discover Services** | ✅ Full | ✅ Full | ✅ Full | ✅ BlueZ | ⚠️ Limited | ✅ WinRT | Low | MVP |
| **Central: Read/Write/Notify** | ✅ Full | ✅ Full | ✅ Full | ✅ BlueZ | ⚠️ Limited | ✅ WinRT | Low | MVP |
| **Central: MTU Request** | ✅ Full | ✅ Auto | ✅ Auto | ⚠️ Partial | ❌ No | ✅ WinRT | Low | MVP |
| **Central: Bond/Pair** | ✅ Full | ✅ Auto | ✅ Auto | ⚠️ Partial | ❌ No | ✅ WinRT | Med | Phase 2 |
| **Peripheral: Advertise** | ✅ API 21+ | ✅ Full | ✅ Full | ⚠️ BlueZ | ❌ No | ❌ No | High | MVP |
| **Peripheral: GATT Server** | ✅ API 21+ | ✅ Full | ✅ Full | ⚠️ Partial | ❌ No | ❌ No | High | MVP |
| **Peripheral: Notify/Indicate** | ✅ Full | ✅ Full | ✅ Full | ⚠️ Partial | ❌ No | ❌ No | Med | MVP |
| **Peripheral: Multi-Central** | ✅ Full | ✅ Full | ✅ Full | ❌ No | ❌ No | ❌ No | Med | MVP |
| **Background: iOS Restore** | N/A | ✅ CoreBluetooth | ❌ No | N/A | N/A | N/A | High | Phase 2 |
| **Background: Android FGS** | ✅ ForegroundService | N/A | N/A | N/A | N/A | N/A | High | Phase 2 |
| **Background: Reconnection** | ✅ Full | ✅ Full | ✅ Full | ⚠️ Partial | ❌ No | ⚠️ Partial | High | Phase 2 |
| **Connection Parameters** | ✅ requestConnectionPriority | ⚠️ Read-only | ⚠️ Read-only | ❌ No | ❌ No | ⚠️ Read-only | Med | Phase 2 |
| **L2CAP Channels** | ✅ API 29+ (BluetoothSocket) | ✅ iOS 11+ (CBL2CAPChannel) | ✅ macOS 10.14+ | ❌ No | ❌ No | ❌ No | High | Phase 3 |
| **Windows BLE Central** | N/A | N/A | N/A | N/A | N/A | ✅ WinRT | High | Phase 2 |
| **Unified Error Codes** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Med | MVP |
| **Structured Logging** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | Low | MVP |

### Legend
- ✅ Full = Fully supported by OS APIs, implementable
- ⚠️ Limited/Partial = Possible with caveats (documented)
- ❌ No = Not supported by OS, will return `BleUnsupportedError`

### Platform-Specific Limitations (Important Details)

**iOS Connection Parameters:**
- Cannot *set* connection parameters — iOS manages them automatically
- Can *read* via `CBPeripheral` key-value observation on connection events (undocumented but functional)
- Workaround: request via `CBConnectPeripheralOptionNotifyOnConnectionKey` behaviors

**Android L2CAP:**
- `BluetoothDevice.createL2capChannel(int psm)` available API 29+ (Android 10)
- `BluetoothDevice.createInsecureL2capChannel(int psm)` available API 29+
- Reliable but requires `BLUETOOTH_CONNECT` permission

**iOS L2CAP:**
- `CBPeripheralManager.publishL2CAPChannel(withEncryption:)` iOS 11+
- `CBPeripheral.openL2CAPChannel(_ PSM:)` iOS 11+
- Very reliable, well-documented by Apple

**Web BLE:**
- Web Bluetooth API is Chrome-only, requires HTTPS, user gesture for scan
- No background, no peripheral role, no L2CAP
- Scanning requires explicit service UUID filters (cannot do wildcard scan)
- Good for demos and prototyping, not production BLE apps

**Linux BLE:**
- BlueZ D-Bus API provides central role well
- Peripheral role via BlueZ is possible but complex (RegisterAdvertisement, RegisterApplication)
- No L2CAP from userspace easily

---

## 3. Proposed Repo Structure

```
ble_plus/                                    # MONOREPO root
├── README.md                                # Top-level overview
├── ARCHITECTURE.md                          # This document
├── LICENSE                                  # BSD-3-Clause (pub.dev standard)
├── melos.yaml                               # Melos workspace config for monorepo
│
├── packages/
│   ├── ble_plus/                            # APP-FACING PACKAGE (what users import)
│   │   ├── pubspec.yaml                     # depends on ble_plus_platform_interface
│   │   ├── lib/
│   │   │   ├── ble_plus.dart                # Barrel export
│   │   │   ├── src/
│   │   │   │   ├── ble_central.dart         # BleCentral class (scan/connect/etc)
│   │   │   │   ├── ble_peripheral.dart      # BlePeripheral class (advertise/serve)
│   │   │   │   ├── ble_device.dart          # BleDevice model
│   │   │   │   ├── ble_service.dart         # BleService model
│   │   │   │   ├── ble_characteristic.dart  # BleCharacteristic model
│   │   │   │   ├── ble_descriptor.dart      # BleDescriptor model
│   │   │   │   ├── ble_scan_result.dart     # BleScanResult model
│   │   │   │   ├── ble_connection.dart      # BleConnection (active connection handle)
│   │   │   │   ├── ble_l2cap_channel.dart   # BleL2CapChannel
│   │   │   │   ├── ble_errors.dart          # Unified error types
│   │   │   │   ├── ble_enums.dart           # BleState, ConnectionState, etc.
│   │   │   │   ├── ble_logger.dart          # Configurable logger
│   │   │   │   ├── ble_background.dart      # Background mode APIs
│   │   │   │   └── ble_connection_params.dart # Connection parameter models
│   │   │   └── testing/
│   │   │       └── mock_ble_plus.dart       # Official mock for testing
│   │   ├── test/
│   │   └── example/
│   │       └── lib/main.dart                # Example app
│   │
│   ├── ble_plus_platform_interface/         # PLATFORM INTERFACE PACKAGE
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   ├── ble_plus_platform_interface.dart  # Barrel
│   │   │   ├── src/
│   │   │   │   ├── platform_interface.dart       # Abstract BlePlusPlatform
│   │   │   │   ├── central_platform.dart         # Central role methods
│   │   │   │   ├── peripheral_platform.dart      # Peripheral role methods
│   │   │   │   ├── method_channel_ble_plus.dart  # Default MethodChannel impl
│   │   │   │   ├── types/                        # Shared type definitions
│   │   │   │   │   ├── scan_result.dart
│   │   │   │   │   ├── ble_device.dart
│   │   │   │   │   ├── ble_service.dart
│   │   │   │   │   ├── ble_characteristic.dart
│   │   │   │   │   ├── ble_descriptor.dart
│   │   │   │   │   ├── connection_params.dart
│   │   │   │   │   ├── advertise_settings.dart
│   │   │   │   │   ├── gatt_service_definition.dart
│   │   │   │   │   └── ble_error.dart
│   │   │   │   └── events/                       # Event channel data types
│   │   │   │       ├── scan_event.dart
│   │   │   │       ├── connection_event.dart
│   │   │   │       ├── characteristic_event.dart
│   │   │   │       └── peripheral_event.dart
│   │   └── test/
│   │
│   ├── ble_plus_android/                    # ANDROID PLATFORM PACKAGE
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   └── ble_plus_android.dart        # Registers platform impl
│   │   ├── android/
│   │   │   ├── build.gradle.kts
│   │   │   └── src/main/kotlin/com/example/ble_plus/
│   │   │       ├── BlePlusPlugin.kt         # Plugin entry, channel setup
│   │   │       ├── CentralManager.kt        # Scanner + GATT client
│   │   │       ├── PeripheralManager.kt     # Advertiser + GATT server
│   │   │       ├── ConnectionManager.kt     # Connection lifecycle
│   │   │       ├── L2CapManager.kt          # L2CAP channels
│   │   │       ├── BackgroundManager.kt     # Foreground service handling
│   │   │       ├── PermissionHandler.kt     # Runtime permissions
│   │   │       ├── Serializer.kt            # Data serialization helpers
│   │   │       └── ErrorMapper.kt           # Maps Android errors → unified codes
│   │   └── test/
│   │
│   ├── ble_plus_ios/                        # iOS PLATFORM PACKAGE
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   └── ble_plus_ios.dart
│   │   ├── ios/
│   │   │   ├── ble_plus_ios.podspec
│   │   │   └── Classes/
│   │   │       ├── BlePlusPlugin.swift       # Plugin entry
│   │   │       ├── CentralManager.swift      # CBCentralManager wrapper
│   │   │       ├── PeripheralManager.swift   # CBPeripheralManager wrapper
│   │   │       ├── ConnectionHandler.swift   # Connection lifecycle
│   │   │       ├── L2CapHandler.swift        # L2CAP channels
│   │   │       ├── BackgroundRestoration.swift # State restoration
│   │   │       ├── Serializer.swift          # Codable helpers
│   │   │       └── ErrorMapper.swift         # Maps CBErrors → unified codes
│   │   └── test/
│   │
│   ├── ble_plus_macos/                      # macOS PLATFORM PACKAGE
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   └── ble_plus_macos.dart
│   │   ├── macos/
│   │   │   ├── ble_plus_macos.podspec
│   │   │   └── Classes/
│   │   │       ├── BlePlusPlugin.swift
│   │   │       ├── CentralManager.swift
│   │   │       ├── PeripheralManager.swift
│   │   │       └── ErrorMapper.swift
│   │   └── test/
│   │
│   ├── ble_plus_windows/                    # WINDOWS PLATFORM PACKAGE
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   └── ble_plus_windows.dart
│   │   ├── windows/
│   │   │   ├── CMakeLists.txt
│   │   │   └── src/
│   │   │       ├── ble_plus_plugin.cpp
│   │   │       ├── central_manager.cpp       # WinRT BLE central
│   │   │       ├── central_manager.h
│   │   │       └── error_mapper.cpp
│   │   └── test/
│   │
│   ├── ble_plus_linux/                      # LINUX PLATFORM PACKAGE
│   │   ├── pubspec.yaml
│   │   ├── lib/
│   │   │   └── ble_plus_linux.dart
│   │   ├── linux/
│   │   │   ├── CMakeLists.txt
│   │   │   └── src/
│   │   │       ├── ble_plus_plugin.cc
│   │   │       └── bluez_adapter.cc          # D-Bus BlueZ integration
│   │   └── test/
│   │
│   └── ble_plus_web/                        # WEB PLATFORM PACKAGE
│       ├── pubspec.yaml
│       ├── lib/
│       │   └── ble_plus_web.dart            # Web Bluetooth API impl
│       └── test/
│
└── tools/
    ├── integration_tests/                   # Physical device test harness
    └── ci/                                  # GitHub Actions workflows
```

### Key Architecture Decisions

1. **Melos monorepo** — enables `melos bootstrap`, `melos run test`, coordinated versioning
2. **Each platform is its own publishable package** — endorsed plugin pattern
3. **Platform interface is the contract** — all platform packages depend only on interface
4. **App-facing package has ZERO native code** — pure Dart, depends on interface
5. **Central and Peripheral are separate classes** — never mixed in one god object

---

## 4. Public API Proposal

### 4.1 Core Classes

```dart
// ═══════════════════════════════════════════════════════════
// ble_plus.dart — Main barrel export
// ═══════════════════════════════════════════════════════════

library ble_plus;

export 'src/ble_central.dart';
export 'src/ble_peripheral.dart';
export 'src/ble_device.dart';
export 'src/ble_service.dart';
export 'src/ble_characteristic.dart';
export 'src/ble_descriptor.dart';
export 'src/ble_scan_result.dart';
export 'src/ble_connection.dart';
export 'src/ble_l2cap_channel.dart';
export 'src/ble_errors.dart';
export 'src/ble_enums.dart';
export 'src/ble_logger.dart';
export 'src/ble_background.dart';
export 'src/ble_connection_params.dart';
```

### 4.2 BleCentral — Central Role API

```dart
/// The central role manager. One instance per app (but NOT a hidden singleton).
/// Create via `BleCentral()` — internally routes to platform.
class BleCentral {
  /// Factory constructor that returns the platform-bound instance.
  factory BleCentral({BleLogger? logger}) => BleCentral._(logger: logger);
  
  // ─── Adapter State ───────────────────────────────────────
  
  /// Stream of adapter state changes (off, on, unauthorized, etc.)
  Stream<BleAdapterState> get adapterState;
  
  /// Current adapter state (synchronous, cached)
  BleAdapterState get currentAdapterState;
  
  /// Request user to turn on Bluetooth (Android only, no-op on iOS)
  Future<bool> requestEnable();
  
  // ─── Scanning ────────────────────────────────────────────
  
  /// Start scanning for BLE peripherals.
  /// Returns a broadcast stream of scan results.
  /// Automatically stops after [timeout] if provided.
  Stream<BleScanResult> startScan({
    List<Guid>? withServices,
    Duration? timeout,
    bool allowDuplicates = false,
    ScanMode scanMode = ScanMode.lowLatency,
  });
  
  /// Stop scanning explicitly.
  Future<void> stopScan();
  
  /// Whether currently scanning.
  bool get isScanning;
  
  /// Stream that emits true/false for scanning state changes.
  Stream<bool> get isScanningStream;
  
  // ─── Connection ──────────────────────────────────────────
  
  /// Connect to a device. Returns a [BleConnection] handle.
  /// Throws [BleConnectionException] on failure.
  Future<BleConnection> connect(
    BleDevice device, {
    Duration timeout = const Duration(seconds: 15),
    bool autoConnect = false, // Android only
  });
  
  /// Get all currently connected devices (system-wide, if platform allows).
  Future<List<BleDevice>> get connectedDevices;
  
  // ─── Background ──────────────────────────────────────────
  
  /// Enable background BLE operations.
  /// On iOS: enables state restoration.
  /// On Android: starts foreground service.
  Future<void> enableBackground({
    String? androidNotificationTitle,
    String? androidNotificationBody,
    String? iosRestorationIdentifier,
  });
  
  /// Disable background mode and release resources.
  Future<void> disableBackground();
  
  /// Stream of restored devices (iOS state restoration).
  Stream<List<BleDevice>> get restoredDevices;
  
  // ─── Cleanup ─────────────────────────────────────────────
  
  /// Release all resources. Call when done with BLE.
  Future<void> dispose();
}
```

### 4.3 BleConnection — Active Connection Handle

```dart
/// Represents an active connection to a BLE peripheral.
/// Obtained from [BleCentral.connect].
/// All operations on a connected device go through this object.
class BleConnection {
  /// The remote device.
  BleDevice get device;
  
  /// Current connection state.
  BleConnectionState get state;
  
  /// Stream of connection state changes.
  Stream<BleConnectionState> get stateStream;
  
  /// Whether still connected.
  bool get isConnected;
  
  // ─── Service Discovery ───────────────────────────────────
  
  /// Discover all services on the remote device.
  Future<List<BleService>> discoverServices();
  
  /// Get previously discovered services (cached after discovery).
  List<BleService> get services;
  
  // ─── Read / Write / Notify ───────────────────────────────
  
  /// Read a characteristic value.
  Future<List<int>> readCharacteristic(BleCharacteristic characteristic);
  
  /// Write a characteristic value.
  Future<void> writeCharacteristic(
    BleCharacteristic characteristic,
    List<int> value, {
    bool withResponse = true,
  });
  
  /// Subscribe to characteristic notifications/indications.
  /// Returns a stream of value updates.
  Stream<List<int>> subscribeToCharacteristic(BleCharacteristic characteristic);
  
  /// Unsubscribe from characteristic notifications.
  Future<void> unsubscribeFromCharacteristic(BleCharacteristic characteristic);
  
  /// Read a descriptor value.
  Future<List<int>> readDescriptor(BleDescriptor descriptor);
  
  /// Write a descriptor value.
  Future<void> writeDescriptor(BleDescriptor descriptor, List<int> value);
  
  // ─── MTU ─────────────────────────────────────────────────
  
  /// Request MTU size. Returns the negotiated MTU.
  /// On iOS this is automatic — returns current MTU.
  Future<int> requestMtu(int desiredMtu);
  
  /// Current MTU value.
  int get mtu;
  
  /// Stream of MTU changes.
  Stream<int> get mtuStream;
  
  // ─── Connection Parameters ───────────────────────────────
  
  /// Get current connection parameters (if available).
  Future<BleConnectionParameters?> getConnectionParameters();
  
  /// Request specific connection parameters.
  /// Android: maps to requestConnectionPriority().
  /// iOS: not supported (returns current params read-only).
  Future<BleConnectionParameters?> requestConnectionParameters(
    ConnectionPriority priority,
  );
  
  // ─── RSSI ────────────────────────────────────────────────
  
  /// Read RSSI of connected device.
  Future<int> readRssi();
  
  // ─── L2CAP ───────────────────────────────────────────────
  
  /// Open an L2CAP channel (CoC) to the remote device.
  /// Throws [BleUnsupportedError] on platforms that don't support it.
  Future<BleL2CapChannel> openL2CapChannel(int psm, {bool secure = true});
  
  // ─── Disconnect ──────────────────────────────────────────
  
  /// Disconnect from the device and release resources.
  Future<void> disconnect();
}
```

### 4.4 BlePeripheral — Peripheral/Server Role API

```dart
/// The peripheral (server) role manager.
/// Allows the app to advertise as a BLE peripheral and serve GATT services.
class BlePeripheral {
  factory BlePeripheral({BleLogger? logger}) => BlePeripheral._(logger: logger);
  
  // ─── Advertising ─────────────────────────────────────────
  
  /// Start advertising with given settings.
  Future<void> startAdvertising(AdvertiseSettings settings);
  
  /// Stop advertising.
  Future<void> stopAdvertising();
  
  /// Whether currently advertising.
  bool get isAdvertising;
  
  /// Stream of advertising state changes.
  Stream<bool> get isAdvertisingStream;
  
  // ─── GATT Server ─────────────────────────────────────────
  
  /// Add a service to the local GATT database.
  /// Must be called before startAdvertising() or while advertising.
  Future<void> addService(GattServiceDefinition service);
  
  /// Remove a service from the local GATT database.
  Future<void> removeService(Guid serviceUuid);
  
  /// Remove all services.
  Future<void> removeAllServices();
  
  // ─── Incoming Events ─────────────────────────────────────
  
  /// Stream of central devices that connect to us.
  Stream<BleDevice> get onCentralConnected;
  
  /// Stream of central devices that disconnect.
  Stream<BleDevice> get onCentralDisconnected;
  
  /// Stream of read requests from centrals.
  Stream<ReadRequest> get onReadRequest;
  
  /// Stream of write requests from centrals.
  Stream<WriteRequest> get onWriteRequest;
  
  /// Called when a central subscribes to notifications on a characteristic.
  Stream<SubscriptionChange> get onSubscriptionChange;
  
  // ─── Sending Data ────────────────────────────────────────
  
  /// Send a notification/indication to subscribed centrals.
  Future<void> notifyCharacteristic(
    Guid serviceUuid,
    Guid characteristicUuid,
    List<int> value, {
    BleDevice? toDevice, // null = all subscribed
  });
  
  // ─── L2CAP (Server side) ─────────────────────────────────
  
  /// Publish an L2CAP channel and listen for incoming connections.
  /// Returns the PSM to advertise.
  Future<int> publishL2CapChannel({bool secure = true});
  
  /// Stream of incoming L2CAP channel connections.
  Stream<BleL2CapChannel> get onL2CapChannelOpened;
  
  /// Unpublish the L2CAP channel.
  Future<void> unpublishL2CapChannel();
  
  // ─── Cleanup ─────────────────────────────────────────────
  
  Future<void> dispose();
}
```

### 4.5 Supporting Models

```dart
/// Represents a BLE device (remote or local).
class BleDevice {
  final String id;           // Platform-specific ID (MAC on Android, UUID on iOS)
  final String? name;        // Local name from advertisement or GAP
  final String? platformName; // Name from platform cache
  
  String get displayName => name ?? platformName ?? 'Unknown';
}

/// A discovered BLE service.
class BleService {
  final Guid uuid;
  final List<BleCharacteristic> characteristics;
  final bool isPrimary;
  final List<BleService> includedServices;
}

/// A BLE characteristic.
class BleCharacteristic {
  final Guid uuid;
  final Guid serviceUuid;
  final BleDevice device;
  final CharacteristicProperties properties;
  final List<BleDescriptor> descriptors;
  List<int> get lastValue; // Last known value (cached)
}

/// Characteristic properties flags.
class CharacteristicProperties {
  final bool read;
  final bool write;
  final bool writeWithoutResponse;
  final bool notify;
  final bool indicate;
  final bool authenticatedSignedWrites;
  final bool extendedProperties;
}

/// A BLE descriptor.
class BleDescriptor {
  final Guid uuid;
  final Guid characteristicUuid;
  final Guid serviceUuid;
}

/// Scan result from a BLE scan.
class BleScanResult {
  final BleDevice device;
  final int rssi;
  final DateTime timestamp;
  final AdvertisementData advertisementData;
}

/// Parsed advertisement data.
class AdvertisementData {
  final String? localName;
  final int? txPowerLevel;
  final bool connectable;
  final Map<int, List<int>> manufacturerData;  // Company ID → data
  final Map<Guid, List<int>> serviceData;      // Service UUID → data
  final List<Guid> serviceUuids;
}

/// Settings for peripheral advertising.
class AdvertiseSettings {
  final String? localName;
  final List<Guid> serviceUuids;
  final Map<int, List<int>>? manufacturerData;
  final int? txPowerLevel;
  final bool connectable;
  final Duration? timeout; // Auto-stop after duration (Android)
}

/// GATT service definition for peripheral mode.
class GattServiceDefinition {
  final Guid uuid;
  final bool isPrimary;
  final List<GattCharacteristicDefinition> characteristics;
}

/// GATT characteristic definition for peripheral mode.
class GattCharacteristicDefinition {
  final Guid uuid;
  final CharacteristicProperties properties;
  final CharacteristicPermissions permissions;
  final List<int>? initialValue;
  final List<GattDescriptorDefinition> descriptors;
}

/// Permissions for a GATT characteristic.
class CharacteristicPermissions {
  final bool read;
  final bool write;
  final bool readEncrypted;
  final bool writeEncrypted;
}

/// Connection parameters.
class BleConnectionParameters {
  final double? connectionIntervalMs; // In milliseconds
  final int? slaveLatency;
  final int? supervisionTimeoutMs;
  final int? mtu;
}

/// Connection priority levels (Android mapping).
enum ConnectionPriority {
  balanced,   // ~30ms interval
  high,       // ~7.5ms interval
  lowPower,   // ~100ms interval
}

/// Read request from a central (peripheral mode).
class ReadRequest {
  final BleDevice central;
  final Guid characteristicUuid;
  final Guid serviceUuid;
  final int offset;
  
  /// Respond to the read request.
  Future<void> respond(List<int> value);
  
  /// Respond with an error.
  Future<void> respondWithError(GattError error);
}

/// Write request from a central (peripheral mode).
class WriteRequest {
  final BleDevice central;
  final Guid characteristicUuid;
  final Guid serviceUuid;
  final List<int> value;
  final int offset;
  final bool responseNeeded;
  
  /// Respond to the write request (if responseNeeded).
  Future<void> respond();
  
  /// Respond with an error.
  Future<void> respondWithError(GattError error);
}

/// Subscription change event.
class SubscriptionChange {
  final BleDevice central;
  final Guid characteristicUuid;
  final Guid serviceUuid;
  final bool isSubscribed;
}
```

### 4.6 L2CAP Channel API

```dart
/// An L2CAP CoC (Connection-Oriented Channel).
class BleL2CapChannel {
  /// The PSM this channel operates on.
  int get psm;
  
  /// The remote device.
  BleDevice get device;
  
  /// Stream of incoming data.
  Stream<List<int>> get inputStream;
  
  /// Write data to the channel.
  Future<void> write(List<int> data);
  
  /// Close the channel.
  Future<void> close();
  
  /// Whether the channel is open.
  bool get isOpen;
  
  /// Stream that emits when channel closes.
  Stream<void> get onClose;
}
```

### 4.7 Unified Error Handling

```dart
/// Base class for all BLE errors.
sealed class BleError implements Exception {
  final String message;
  final int? platformCode;
  final String? platformMessage;
  
  const BleError(this.message, {this.platformCode, this.platformMessage});
}

/// The requested feature is not supported on this platform.
class BleUnsupportedError extends BleError {
  const BleUnsupportedError(super.message);
}

/// Bluetooth adapter is not available or turned off.
class BleAdapterError extends BleError {
  final BleAdapterState state;
  const BleAdapterError(super.message, {required this.state});
}

/// Connection failed or was lost.
class BleConnectionError extends BleError {
  final BleDevice? device;
  const BleConnectionError(super.message, {this.device, super.platformCode});
}

/// GATT operation failed.
class BleGattError extends BleError {
  final GattErrorCode code;
  const BleGattError(super.message, {required this.code, super.platformCode});
}

/// Scan error.
class BleScanError extends BleError {
  const BleScanError(super.message, {super.platformCode});
}

/// Permission denied.
class BlePermissionError extends BleError {
  final List<String> missingPermissions;
  const BlePermissionError(super.message, {required this.missingPermissions});
}

/// Timeout.
class BleTimeoutError extends BleError {
  const BleTimeoutError(super.message);
}

/// Unified GATT error codes across platforms.
enum GattErrorCode {
  success,
  invalidHandle,
  readNotPermitted,
  writeNotPermitted,
  invalidPdu,
  insufficientAuthentication,
  requestNotSupported,
  invalidOffset,
  insufficientEncryption,
  connectionCongested,
  failure,
  unknown,
}
```

### 4.8 Logger

```dart
/// Configurable BLE logger.
class BleLogger {
  BleLogLevel level;
  void Function(BleLogLevel level, String tag, String message)? onLog;
  
  BleLogger({this.level = BleLogLevel.warning, this.onLog});
}

enum BleLogLevel { verbose, debug, info, warning, error, none }
```

### 4.9 Enums

```dart
enum BleAdapterState {
  unknown,
  unsupported,
  unauthorized,
  turningOn,
  on,
  turningOff,
  off,
}

enum BleConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

enum ScanMode {
  lowPower,     // Android SCAN_MODE_LOW_POWER
  balanced,     // Android SCAN_MODE_BALANCED
  lowLatency,   // Android SCAN_MODE_LOW_LATENCY
  opportunistic, // Android SCAN_MODE_OPPORTUNISTIC
}
```

---

## 5. Platform Interface Design

### 5.1 Abstract Platform Interface

```dart
/// The platform interface contract.
/// All platform packages implement this.
abstract class BlePlusPlatform extends PlatformInterface {
  BlePlusPlatform() : super(token: _token);
  static final Object _token = Object();
  
  static BlePlusPlatform _instance = _DefaultNoOpPlatform();
  static BlePlusPlatform get instance => _instance;
  static set instance(BlePlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }
  
  // ─── Adapter ─────────────────────────────────────────────
  Stream<BleAdapterState> get adapterStateStream;
  Future<bool> requestEnable();
  
  // ─── Central: Scanning ───────────────────────────────────
  Stream<BleScanResultData> startScan(ScanSettings settings);
  Future<void> stopScan();
  Stream<bool> get isScanningStream;
  
  // ─── Central: Connection ─────────────────────────────────
  Future<void> connect(String deviceId, ConnectionSettings settings);
  Future<void> disconnect(String deviceId);
  Stream<BleConnectionEvent> get connectionEventStream;
  
  // ─── Central: GATT Operations ────────────────────────────
  Future<List<BleServiceData>> discoverServices(String deviceId);
  Future<List<int>> readCharacteristic(String deviceId, String serviceUuid, String charUuid);
  Future<void> writeCharacteristic(String deviceId, String serviceUuid, String charUuid, List<int> value, bool withResponse);
  Future<void> setNotification(String deviceId, String serviceUuid, String charUuid, bool enable);
  Stream<CharacteristicValueEvent> get characteristicValueStream;
  Future<List<int>> readDescriptor(String deviceId, String serviceUuid, String charUuid, String descUuid);
  Future<void> writeDescriptor(String deviceId, String serviceUuid, String charUuid, String descUuid, List<int> value);
  
  // ─── Central: MTU ────────────────────────────────────────
  Future<int> requestMtu(String deviceId, int mtu);
  Stream<MtuChangeEvent> get mtuChangeStream;
  
  // ─── Central: RSSI ───────────────────────────────────────
  Future<int> readRssi(String deviceId);
  
  // ─── Central: Connection Parameters ──────────────────────
  Future<BleConnectionParametersData?> getConnectionParameters(String deviceId);
  Future<BleConnectionParametersData?> requestConnectionPriority(String deviceId, int priority);
  
  // ─── Central: L2CAP ──────────────────────────────────────
  Future<int> openL2CapChannel(String deviceId, int psm, bool secure);
  Future<void> closeL2CapChannel(int channelId);
  Future<void> writeL2Cap(int channelId, List<int> data);
  Stream<L2CapDataEvent> get l2capDataStream;
  Stream<L2CapCloseEvent> get l2capCloseStream;
  
  // ─── Peripheral: Advertising ─────────────────────────────
  Future<void> startAdvertising(AdvertiseSettingsData settings);
  Future<void> stopAdvertising();
  Stream<bool> get isAdvertisingStream;
  
  // ─── Peripheral: GATT Server ─────────────────────────────
  Future<void> addService(GattServiceDefinitionData service);
  Future<void> removeService(String uuid);
  Future<void> removeAllServices();
  Future<void> sendNotification(String serviceUuid, String charUuid, List<int> value, String? deviceId);
  Future<void> respondToReadRequest(int requestId, List<int> value);
  Future<void> respondToWriteRequest(int requestId);
  Future<void> respondWithError(int requestId, int errorCode);
  
  // ─── Peripheral: Events ──────────────────────────────────
  Stream<PeripheralConnectionEvent> get peripheralConnectionStream;
  Stream<ReadRequestEvent> get readRequestStream;
  Stream<WriteRequestEvent> get writeRequestStream;
  Stream<SubscriptionChangeEvent> get subscriptionChangeStream;
  
  // ─── Peripheral: L2CAP Server ────────────────────────────
  Future<int> publishL2CapChannel(bool secure);
  Future<void> unpublishL2CapChannel();
  Stream<L2CapChannelOpenedEvent> get l2capServerChannelStream;
  
  // ─── Background ──────────────────────────────────────────
  Future<void> enableBackground(BackgroundSettings settings);
  Future<void> disableBackground();
  Stream<List<String>> get restoredDeviceIdsStream;
  
  // ─── Capabilities ────────────────────────────────────────
  /// Reports what this platform supports.
  PlatformCapabilities get capabilities;
}

/// Declares what features this platform actually supports.
class PlatformCapabilities {
  final bool centralRole;
  final bool peripheralRole;
  final bool l2cap;
  final bool backgroundCentral;
  final bool backgroundPeripheral;
  final bool connectionParameters;
  final bool requestMtu;
  final bool bondManagement;
}
```

### 5.2 Internal Data Flow

```
┌─────────────────┐     ┌──────────────────────┐     ┌─────────────────────┐
│   App Code      │     │  ble_plus (Dart)      │     │  Platform Package   │
│                 │     │                        │     │  (Android/iOS/etc)  │
│  BleCentral     │────▶│  BlePlusPlatform      │────▶│  MethodChannel /    │
│  BlePeripheral  │◀────│  .instance            │◀────│  EventChannel       │
│  BleConnection  │     │                        │     │                     │
└─────────────────┘     └──────────────────────┘     └─────────────────────┘
                                                              │
                                                              ▼
                                                      ┌─────────────────┐
                                                      │  Native Layer   │
                                                      │  (Kotlin/Swift/ │
                                                      │   C++/BlueZ)    │
                                                      └─────────────────┘
```

**Channel Architecture (per platform):**

| Channel | Type | Purpose |
|---------|------|---------|
| `ble_plus/methods` | MethodChannel | All request/response operations |
| `ble_plus/events/adapter` | EventChannel | Adapter state stream |
| `ble_plus/events/scan` | EventChannel | Scan results stream |
| `ble_plus/events/connection` | EventChannel | Connection state events |
| `ble_plus/events/characteristic` | EventChannel | Characteristic value updates |
| `ble_plus/events/mtu` | EventChannel | MTU change events |
| `ble_plus/events/peripheral` | EventChannel | Peripheral role events (read/write requests, connections) |
| `ble_plus/events/l2cap` | EventChannel | L2CAP data events |

**Why multiple EventChannels instead of one:**
- Avoids a single bottleneck stream that requires demultiplexing
- Each stream can be independently listened/cancelled
- Matches Flutter's stream disposal patterns
- Platform can use separate handler threads per concern

---

## 6. Native Implementation Notes

### 6.1 Android (Kotlin)

**Minimum SDK:** API 21 (Android 5.0) for BLE, API 29 for L2CAP  
**Target SDK:** 34+

**Required Permissions (declared in manifest):**
```xml
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />
<uses-feature android:name="android.hardware.bluetooth_le" android:required="false" />
```

**Key Native Classes:**

| File | Class | Native APIs Used |
|------|-------|-----------------|
| `BlePlusPlugin.kt` | `BlePlusPlugin` | `FlutterPlugin`, `ActivityAware`, `MethodCallHandler` |
| `CentralManager.kt` | `CentralManager` | `BluetoothLeScanner`, `BluetoothGatt`, `BluetoothGattCallback` |
| `PeripheralManager.kt` | `PeripheralManager` | `BluetoothLeAdvertiser`, `BluetoothGattServer`, `BluetoothGattServerCallback` |
| `ConnectionManager.kt` | `ConnectionManager` | `BluetoothGatt.connect()`, `BluetoothGattCallback.onConnectionStateChange` |
| `L2CapManager.kt` | `L2CapManager` | `BluetoothDevice.createL2capChannel()`, `BluetoothServerSocket` |
| `BackgroundManager.kt` | `BackgroundManager` | `ForegroundService`, `NotificationChannel` |
| `PermissionHandler.kt` | `PermissionHandler` | `ActivityCompat.requestPermissions()` |

**Android-Specific Implementation Details:**

1. **GATT Operation Queue:** Android allows only one outstanding GATT operation at a time. Implement a `Mutex`/`Semaphore` in `ConnectionManager` that serializes `readCharacteristic`, `writeCharacteristic`, `readDescriptor`, `writeDescriptor`, `requestMtu`, `readRssi`.

2. **Connection Priority:** `BluetoothGatt.requestConnectionPriority(int)` maps to:
   - `CONNECTION_PRIORITY_BALANCED` = 0
   - `CONNECTION_PRIORITY_HIGH` = 1  
   - `CONNECTION_PRIORITY_LOW_POWER` = 2

3. **Foreground Service (Phase 2):**
   - Requires `FOREGROUND_SERVICE_CONNECTED_DEVICE` (API 34+)
   - Service type: `connectedDevice`
   - Must show persistent notification
   - Plugin provides a default service; user can customize

4. **Multi-connection:** Android supports 7 simultaneous GATT client connections (hardware-dependent). GATT server supports multiple centrals natively.

5. **L2CAP:** 
   - `BluetoothDevice.createL2capChannel(int psm)` — secure
   - `BluetoothDevice.createInsecureL2capChannel(int psm)` — insecure
   - Server: `BluetoothAdapter.listenUsingL2capChannel()` returns `BluetoothServerSocket`
   - Runs on background threads; communicate results back via EventChannel

### 6.2 iOS (Swift)

**Minimum iOS:** 13.0  
**Frameworks:** CoreBluetooth

**Key Native Classes:**

| File | Class | Native APIs Used |
|------|-------|-----------------|
| `BlePlusPlugin.swift` | `BlePlusPlugin` | `FlutterPlugin` registration |
| `CentralManager.swift` | `CentralManagerHandler` | `CBCentralManager`, `CBCentralManagerDelegate` |
| `PeripheralManager.swift` | `PeripheralManagerHandler` | `CBPeripheralManager`, `CBPeripheralManagerDelegate` |
| `ConnectionHandler.swift` | `ConnectionHandler` | `CBPeripheral`, `CBPeripheralDelegate` |
| `L2CapHandler.swift` | `L2CapHandler` | `CBL2CAPChannel`, `peripheral.openL2CAPChannel()` |
| `BackgroundRestoration.swift` | `BackgroundRestoration` | `CBCentralManagerOptionRestoreIdentifierKey` |
| `Serializer.swift` | `Serializer` | Codable to/from FlutterStandardTypedData |

**iOS-Specific Implementation Details:**

1. **State Restoration (Phase 2):**
   - Initialize with: `CBCentralManager(delegate:, queue:, options: [CBCentralManagerOptionRestoreIdentifierKey: "ble_plus_central"])`
   - Implement `centralManager(_:willRestoreState:)` delegate method
   - App must add `bluetooth-central` to `UIBackgroundModes` in Info.plist
   - Restored peripherals arrive in `CBCentralManagerRestoredStatePeripheralsKey`

2. **Peripheral Mode:**
   - `CBPeripheralManager` for advertising and GATT server
   - `peripheralManager.add(CBMutableService)` to add services
   - `peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [...]])` 
   - Delegates: `peripheralManager(_:didReceiveRead:)`, `peripheralManager(_:didReceiveWrite:)`
   - `peripheralManager.updateValue(_:for:onSubscribedCentrals:)` for notifications

3. **L2CAP:**
   - Server: `peripheralManager.publishL2CAPChannel(withEncryption: true)` → `peripheralManagerDidPublishL2CAPChannel` callback gives PSM
   - Client: `peripheral.openL2CAPChannel(psm)` → `peripheral(_:didOpen:error:)` callback
   - Channel provides `inputStream` and `outputStream` (Foundation streams)
   - Must handle stream scheduling on RunLoop

4. **Connection Parameters:** 
   - iOS does NOT expose `requestConnectionParameters()` 
   - Connection interval is managed by iOS automatically
   - Can READ parameters indirectly when `peripheral(_:didUpdateValueFor:)` returns timing info (no public API)
   - Best practice: document this limitation clearly

5. **Scanning:**
   - `CBCentralManager.scanForPeripherals(withServices:options:)`
   - `allowDuplicates`: `CBCentralManagerScanOptionAllowDuplicatesKey`
   - Background scanning: only with specific service UUIDs, no wildcard

6. **Thread Model:** All CoreBluetooth callbacks on a dedicated serial `DispatchQueue`, results dispatched to main thread for Flutter.

### 6.3 macOS (Swift)

**Minimum macOS:** 10.15  
**Framework:** CoreBluetooth (same as iOS)

**Differences from iOS:**
- No background modes (macOS apps stay running)
- No state restoration needed
- Requires App Sandbox entitlement: `com.apple.security.device.bluetooth`
- `CBPeripheralManager` available for peripheral mode
- L2CAP available macOS 10.14+
- Use `import FlutterMacOS` instead of `import Flutter`
- No `UIDevice` — use `ProcessInfo` for version

**Files:** Mirror iOS structure but in `macos/Classes/`. Can share 90% of code via shared Swift files or a shared framework.

### 6.4 Windows (C++ / WinRT)

**Phase 2 — Central Only Initially**

**APIs:**
- `Windows.Devices.Bluetooth` namespace
- `BluetoothLEAdvertisementWatcher` for scanning
- `BluetoothLEDevice.FromBluetoothAddressAsync()` for connection
- `GattDeviceService`, `GattCharacteristic` for GATT operations
- `GattSession` for MTU

**Implementation Notes:**
- Use C++/WinRT projections
- Windows does NOT support peripheral/GATT server role from UWP/WinRT APIs
- L2CAP not available on Windows BLE stack
- Connection parameters: read-only via `BluetoothLEDevice.ConnectionStatus`

**Recommendation:** Implement as endorsed `ble_plus_windows` package. Start with Central role only. Peripheral mode is NOT possible on Windows — return `BleUnsupportedError`.

### 6.5 Linux (C / BlueZ D-Bus)

**Phase 3**

**APIs:**
- BlueZ D-Bus API: `org.bluez.Adapter1`, `org.bluez.Device1`, `org.bluez.GattManager1`
- Scanning: `Adapter1.StartDiscovery()`, listen for `InterfacesAdded` signals
- Connection: `Device1.Connect()`
- GATT: `org.bluez.GattCharacteristic1.ReadValue()`, `.WriteValue()`, `.StartNotify()`
- Peripheral: `org.bluez.LEAdvertisingManager1.RegisterAdvertisement()`, `org.bluez.GattManager1.RegisterApplication()`

**Implementation Notes:**
- Use `dbus` package or FFI to BlueZ C library
- Peripheral mode is possible but complex (requires root or correct D-Bus policies)
- L2CAP not practical from userspace via D-Bus
- Recommend using `bluez_dbus` Dart package or native C plugin

### 6.6 Web (Dart / Web Bluetooth API)

**Heavily Limited — Phase 3**

**APIs:**
- `navigator.bluetooth.requestDevice()` — requires user gesture
- `BluetoothDevice.gatt.connect()`
- `BluetoothRemoteGATTService`, `BluetoothRemoteGATTCharacteristic`

**Limitations:**
- No background support
- No peripheral/server role
- No L2CAP
- No scanning without service UUID filter
- Chrome-only (no Firefox, no Safari)
- HTTPS required
- Each operation requires prior user gesture for security

**Recommendation:** Implement basic Central: scan (with service filter), connect, discover, read, write, notify. Everything else returns `BleUnsupportedError`.

---

## 7. Development Roadmap

### MVP (Phase 1) — 8-10 weeks

**Goal:** Ship a working plugin with Central + Peripheral on Android and iOS.

| Week | Deliverable |
|------|-------------|
| 1-2 | Monorepo setup with Melos. Platform interface package with all type definitions. App-facing package with API classes (stubs). |
| 3-4 | Android Central: scan, connect, discover, read/write/notify, MTU, disconnect |
| 5-6 | iOS Central: scan, connect, discover, read/write/notify, MTU, disconnect |
| 7 | Android Peripheral: advertise, GATT server, read/write callbacks, notify |
| 8 | iOS Peripheral: advertise, GATT server, read/write callbacks, notify |
| 9 | Unified error handling, logging, example app, documentation |
| 10 | Testing, bug fixes, pub.dev publish preparation |

**MVP Scope:**
- ✅ `BleCentral` full API on Android + iOS
- ✅ `BlePeripheral` full API on Android + iOS  
- ✅ Unified error types
- ✅ Configurable logging
- ✅ Example app with scan/connect/peripheral demo
- ✅ Unit tests + mock platform tests
- ❌ No L2CAP
- ❌ No background mode
- ❌ No connection parameters
- ❌ No Windows/Linux/Web

### Phase 2 — 6-8 weeks

| Week | Deliverable |
|------|-------------|
| 1-2 | macOS support (Central + Peripheral) — code sharing with iOS |
| 3-4 | Background support: iOS state restoration, Android foreground service |
| 5 | Connection parameters API (Android requestConnectionPriority, iOS read-only) |
| 6 | L2CAP support on iOS + Android |
| 7-8 | Windows Central role (WinRT) |

**Phase 2 Scope:**
- ✅ macOS platform package
- ✅ Background/restoration APIs  
- ✅ Connection parameters
- ✅ L2CAP channels (iOS + Android)
- ✅ Windows Central (endorsed package)
- ✅ Integration tests on physical devices

### Phase 3 — 4-6 weeks

| Week | Deliverable |
|------|-------------|
| 1-2 | Linux support (BlueZ, Central only initially) |
| 3 | Web support (basic Central) |
| 4 | Bond/Pair management APIs |
| 5-6 | Performance optimization, edge case fixes, documentation polish |

**Phase 3 Scope:**
- ✅ Linux Central (BlueZ D-Bus)
- ✅ Web Central (basic)
- ✅ Bonding APIs
- ✅ Full documentation site
- ✅ Migration guide from flutter_blue_plus

---

## 8. Risks and Limitations

### Hard Platform Limitations (Cannot Be Solved)

| Limitation | Platform | Detail |
|-----------|----------|--------|
| No peripheral mode | Windows, Web | WinRT and Web Bluetooth have no GATT server APIs |
| No L2CAP | Windows, Linux, Web | OS APIs don't expose L2CAP at the BLE level |
| No connection param control | iOS | iOS manages connection parameters internally; read-only at best |
| No background scanning without UUIDs | iOS | CoreBluetooth requires service UUIDs for background scan |
| No wildcard scan on Web | Web | Web Bluetooth requires service UUID filter |
| Limited concurrent connections | Android | Hardware-dependent, typically 7 max |
| Advertising data size | All | BLE 4.x: 31 bytes. BLE 5.x: 255 bytes (extended advertising) |
| MTU negotiation | iOS | iOS auto-negotiates, app cannot request specific MTU |

### Architectural Risks

| Risk | Mitigation |
|------|-----------|
| Android GATT instability (error 133, 8) | Implement retry logic, connection queue, proper cleanup on disconnect |
| iOS CoreBluetooth background killing | State restoration + proper `willRestoreState` implementation |
| Stream subscription leaks | Use `BroadcastStream` with auto-cleanup on connection loss; provide `dispose()` on every object |
| Race conditions in GATT operations | Per-device operation mutex (similar to flutter_blue_plus but per-connection, not global) |
| Platform packages getting out of sync | Melos workspace with coordinated versioning, shared CI |
| Pub.dev score requirements | Strict linting, documentation coverage, example app, platform support matrix in pubspec |

### "Possible But Difficult" Features

| Feature | Difficulty | Notes |
|---------|-----------|-------|
| Android foreground service | Hard | Requires Activity binding, notification channels, proper lifecycle. Can't be purely in plugin — app must declare service in manifest |
| iOS state restoration | Hard | Requires precise implementation of `willRestoreState`, correct identifier management, and app must handle cold-start reconnection |
| Linux peripheral mode | Very Hard | Requires BlueZ D-Bus `RegisterApplication` + `RegisterAdvertisement`, proper D-Bus policy files, often needs root |
| Windows scanning | Medium | WinRT async patterns with C++ are verbose but well-documented |

---

## 9. Testing Plan

### 9.1 Unit Tests (Dart)

```
packages/ble_plus/test/
├── ble_central_test.dart        # Tests BleCentral with mock platform
├── ble_peripheral_test.dart     # Tests BlePeripheral with mock platform
├── ble_connection_test.dart     # Tests BleConnection operations
├── ble_errors_test.dart         # Tests error mapping
├── models/
│   ├── ble_device_test.dart
│   ├── ble_service_test.dart
│   └── scan_result_test.dart
└── streams/
    ├── scan_stream_test.dart    # Tests stream lifecycle, cancellation
    └── notify_stream_test.dart
```

**Mock Strategy:** Provide `MockBlePlusPlatform` in `testing/` directory that implements the full platform interface with configurable behavior.

### 9.2 Platform Interface Tests

```
packages/ble_plus_platform_interface/test/
├── method_channel_test.dart     # Verifies method channel encoding/decoding
└── types_test.dart              # Verifies serialization of all types
```

### 9.3 Integration Tests (Physical Devices)

```
tools/integration_tests/
├── central_scan_test.dart       # Scan for a known test peripheral
├── central_connect_test.dart    # Connect, discover, read/write
├── peripheral_advertise_test.dart # Start advertising, verify from second device
├── peripheral_gatt_test.dart    # Full GATT server test
└── l2cap_test.dart              # L2CAP channel data transfer
```

**Test Hardware Setup:**
- Two physical phones (one Central, one Peripheral)
- Or: one phone + one BLE development board (nRF52840-DK, ESP32)
- CI: cannot reliably test BLE in CI — use manual test runs with documented procedures

### 9.4 CI Strategy

```yaml
# .github/workflows/ci.yml
- Dart analyze + format check on all packages
- Unit tests on all packages (no hardware needed)
- Build Android APK (verifies Kotlin compilation)
- Build iOS (verifies Swift compilation, requires macOS runner)
- Build macOS (verifies macOS Swift)
- Build Windows (verifies C++ compilation)
- Pub score check (pana)
- Documentation generation
```

---

## 10. pub.dev Readiness

### 10.1 Package Naming

| Package | pub.dev name | Description |
|---------|-------------|-------------|
| App-facing | `ble_plus` | Flutter BLE plugin with Central and Peripheral support |
| Interface | `ble_plus_platform_interface` | Platform interface for ble_plus |
| Android | `ble_plus_android` | Android implementation of ble_plus |
| iOS | `ble_plus_ios` | iOS implementation of ble_plus |
| macOS | `ble_plus_macos` | macOS implementation of ble_plus |
| Windows | `ble_plus_windows` | Windows implementation of ble_plus |
| Linux | `ble_plus_linux` | Linux implementation of ble_plus |
| Web | `ble_plus_web` | Web implementation of ble_plus |

### 10.2 Licensing

- **BSD-3-Clause** — standard for Flutter ecosystem packages
- No copyleft, compatible with all app licenses
- Each package has its own LICENSE file

### 10.3 README Requirements (for pub.dev score)

Each package README must include:
- [ ] Description (first paragraph used by pub.dev)
- [ ] Platform support table with version badges
- [ ] Installation instructions
- [ ] Quick start code example
- [ ] API overview with links to API docs
- [ ] Permissions setup guide (Android manifest, iOS Info.plist)
- [ ] Known limitations per platform
- [ ] Contributing guide link
- [ ] License badge

### 10.4 Example App

```
packages/ble_plus/example/
├── lib/
│   ├── main.dart              # Tab-based app with Central and Peripheral tabs
│   ├── central_page.dart      # Scan, connect, discover, read/write demo
│   ├── peripheral_page.dart   # Advertise, serve characteristics demo
│   └── device_detail_page.dart # Connected device interaction
├── android/
│   └── app/src/main/AndroidManifest.xml  # All BLE permissions declared
├── ios/
│   └── Runner/Info.plist      # NSBluetoothAlwaysUsageDescription, background modes
└── pubspec.yaml
```

### 10.5 Versioning Strategy

- Follow **SemVer 2.0**
- All packages version together (Melos `version` command)
- Start at `0.1.0` for MVP (pre-1.0 = breaking changes expected)
- `1.0.0` after Phase 2 completes and API is stable
- Changelog per package, generated via conventional commits

### 10.6 Publish Checklist

- [ ] `dart analyze` passes with zero issues on all packages
- [ ] `dart format` applied
- [ ] All public APIs have dartdoc comments
- [ ] Example app builds and runs on Android + iOS
- [ ] `pana` score ≥ 130/160 (realistic for plugin with native code)
- [ ] Platform support declared in pubspec `platforms:` key
- [ ] `funding`, `repository`, `issue_tracker` URLs in pubspec
- [ ] Screenshots in `pubspec.yaml` (for pub.dev listing)
- [ ] Topics: `ble`, `bluetooth`, `bluetooth-low-energy`, `peripheral`
- [ ] Verified publisher account on pub.dev

---

## 11. Detailed Next Steps (Immediate Action Plan)

### Step 1: Restructure to Monorepo (Day 1-2)

```bash
# From your current ble_plus directory
cd /Users/ajinkya.a/Documents/

# Create monorepo structure
mkdir -p ble_plus_workspace/packages
cd ble_plus_workspace

# Initialize melos
dart pub global activate melos
# Create melos.yaml (provided below)

# Move current scaffold as starting point for android package reference
# But we'll create fresh packages with proper structure
```

### Step 2: Create Platform Interface Package (Day 2-4)

```bash
cd packages
flutter create --template=package ble_plus_platform_interface
```

Define all abstract methods, types, events, and error codes. This is the foundation everything else depends on.

### Step 3: Create App-Facing Package (Day 4-5)

```bash
flutter create --template=package ble_plus
```

Implement `BleCentral`, `BlePeripheral`, `BleConnection` classes that delegate to `BlePlusPlatform.instance`.

### Step 4: Create Android Package (Day 5-7)

```bash
flutter create --template=plugin --platforms=android ble_plus_android
```

Implement `CentralManager.kt` with scanning and connection first. Test on physical device.

### Step 5: Create iOS Package (Week 2)

```bash
flutter create --template=plugin --platforms=ios ble_plus_ios
```

Implement `CentralManager.swift` with scanning and connection. Test on physical device.

### Step 6: Implement GATT Operations (Week 3-4)

Add read/write/notify/discover to both Android and iOS. This is the core of the plugin.

### Step 7: Implement Peripheral Mode (Week 5-6)

Add GATT server + advertising on both platforms. Test with two devices.

### Step 8: Polish and Publish (Week 7-8)

Error handling, logging, example app, documentation, publish to pub.dev.

---

## 12. Key Files to Create First

Here's the priority order for initial implementation:

1. `melos.yaml` — workspace configuration
2. `packages/ble_plus_platform_interface/lib/src/platform_interface.dart` — the contract
3. `packages/ble_plus_platform_interface/lib/src/types/` — all shared types
4. `packages/ble_plus/lib/src/ble_central.dart` — app-facing Central API
5. `packages/ble_plus/lib/src/ble_peripheral.dart` — app-facing Peripheral API
6. `packages/ble_plus_android/android/.../CentralManager.kt` — Android scanning
7. `packages/ble_plus_ios/ios/Classes/CentralManager.swift` — iOS scanning
8. `packages/ble_plus/example/` — working example app

---

## 13. Comparison: ble_plus vs flutter_blue_plus

| Aspect | flutter_blue_plus | ble_plus (new) |
|--------|------------------|----------------|
| Architecture | Monolithic single package | Federated multi-package |
| Global state | `FlutterBluePlus` singleton | Per-instance `BleCentral`/`BlePeripheral` |
| Peripheral mode | ❌ Not supported | ✅ Full API |
| L2CAP | ❌ Not supported | ✅ iOS + Android |
| Background | Partial, undocumented | ✅ Explicit APIs with restoration |
| Connection params | ❌ Not exposed | ✅ Read + request where supported |
| Error handling | Generic `PlatformException` | Sealed `BleError` hierarchy with codes |
| Stream safety | Some dangling stream issues | Lifecycle-bound streams with auto-cleanup |
| Testing | Difficult to mock | Official `MockBlePlusPlatform` provided |
| Multi-platform | Android + iOS (+ partial others) | All 6 platforms with clear capability flags |
| Operation queueing | Global mutex | Per-connection mutex |
| Logging | Basic print | Configurable `BleLogger` with levels |

---

*End of Architecture Document*

