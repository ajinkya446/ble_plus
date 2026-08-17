# ble_plus

A production-ready Flutter BLE plugin with **Central** and **Peripheral** roles across **6 platforms**.

[![pub package](https://img.shields.io/pub/v/ble_plus.svg)](https://pub.dev/packages/ble_plus)

## Features

- **Central Mode**: Scan, connect, discover services, read/write/notify characteristics
- **Peripheral Mode**: Advertise, GATT server, handle read/write requests, send notifications
- **L2CAP Channels**: High-throughput data streaming (iOS 11+, Android 10+, macOS 10.14+)
- **Background Support**: iOS state restoration, Android foreground service, Windows tray (hide to tray on close)
- **Connection Parameters**: Request/inspect connection intervals
- **Descriptor R/W**: Read and write characteristic descriptors
- **Unified Error Handling**: Sealed `BleError` hierarchy with platform error codes
- **Configurable Logging**: Debug, info, warning, error levels with custom callbacks
- **6 Platforms**: Android, iOS, macOS, Web, Linux, Windows

## Platform Support Matrix

| Feature | Android | iOS | macOS | Web | Linux | Windows |
|---------|:-------:|:---:|:-----:|:---:|:-----:|:-------:|
| **Central: Scan** | ✅ | ✅ | ✅ | ✅¹ | ✅ | ✅ |
| **Central: Connect** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Central: GATT R/W/Notify** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Central: Descriptors** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Central: MTU Request** | ✅ | Auto | Auto | Auto | ❌ | Auto |
| **Central: Read RSSI** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Central: Connection Params** | ✅ | Read-only | Read-only | ❌ | ❌ | ❌ |
| **Peripheral: Advertise** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Peripheral: GATT Server** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **Peripheral: Notifications** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **L2CAP Channels** | ✅² | ✅³ | ✅⁴ | ❌ | ❌ | ❌ |
| **Background Mode** | ✅ | ✅ | ❌ | ❌ | ❌ | ✅⁶ |
| **Bond/Pair Management** | ✅ | Auto | Auto | ❌ | ✅ | ✅⁵ |

> ¹ Web scanning uses a device picker dialog (requires user gesture + HTTPS). Chrome/Edge only.  
> ² Android L2CAP requires API 29+ (Android 10).  
> ³ iOS L2CAP requires iOS 11+.  
> ⁴ macOS L2CAP requires macOS 10.14+.  
> ⁵ Windows: `getBondState()` supported; `removeBond()` not available.  
> ⁶ Windows: hides to the tray on close; requires `enableBackground` (the example runner implements it via the `ble_plus/runner_background` channel).

## Platform-Specific Limitations

### Web
- **Central role only** — no peripheral/advertising support (Web Bluetooth API limitation)
- **No L2CAP**, no background mode, no descriptor R/W, no RSSI
- Scanning shows a **device picker dialog** (not continuous scan) — requires user gesture
- Requires **HTTPS** (or localhost for development)
- **Chrome/Edge only** — not supported in Firefox or Safari
- Must specify service UUID filters when scanning (no wildcard scan)

### Linux
- **Central role only** — no peripheral or L2CAP support
- Uses BlueZ D-Bus API — requires `bluez` package installed
- No MTU request, RSSI read, descriptor R/W, or background support
- Scanning requires appropriate D-Bus permissions

### Windows
- **Central role only** — no peripheral or L2CAP support
- Uses WinRT BLE APIs — requires **Windows 10** or later
- No RSSI read, descriptor R/W, or L2CAP support
- MTU is auto-negotiated by the OS
- Background support: with `enableBackground`, closing the window hides it to the system tray instead of terminating the process (BLE keeps running). The example runner implements this via the `ble_plus/runner_background` channel.

### iOS / macOS
- **MTU is auto-negotiated** — `requestMtu()` returns current value but cannot set it
- **Connection parameters are read-only** — iOS/macOS manages intervals automatically
- L2CAP requires iOS 11+ / macOS 10.14+
- Background mode (iOS only) requires `UIBackgroundModes` in Info.plist

### Android
- L2CAP requires **API 29+** (Android 10)
- Peripheral role requires `BLUETOOTH_ADVERTISE` permission (Android 12+)
- `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` + `ACCESS_FINE_LOCATION` required for scanning
- Background mode uses foreground service architecture

## Quick Start

```dart
import 'package:ble_plus/ble_plus.dart';

// ── Central: Scan and Connect ──────────────────────────────
final central = BleCentral();

// Scan for devices
central.startScan(withServices: [Guid('180D')]).listen((result) {
  print('Found: ${result.device.displayName} RSSI: ${result.rssi}');
});

// Connect
final connection = await central.connect(device);
final services = await connection.discoverServices();

// Read a characteristic
final value = await connection.readCharacteristic(char);

// Subscribe to notifications
connection.subscribeToCharacteristic(char).listen((data) {
  print('Notification: $data');
});

// Read/write descriptors
final descValue = await connection.readDescriptor(descriptor);
await connection.writeDescriptor(descriptor, [0x01, 0x00]);

// Read RSSI
final rssi = await connection.readRssi();

// Request connection parameters (Android)
await connection.requestConnectionParameters(ConnectionPriority.high);

// ── Bond / Pair ────────────────────────────────────────────
// Check bond state
final bondState = await connection.bondState; // none, bonding, bonded

// Initiate pairing
await connection.createBond();

// Listen for bond state changes
connection.bondStateStream.listen((state) {
  print('Bond state: $state'); // none → bonding → bonded
});

// Remove bond (Android/Linux)
await connection.removeBond();

// ── Connection State ───────────────────────────────────────
// Check current state
print('Connected: ${connection.isConnected}');
print('State: ${connection.connectionState}');

// Listen for connection state changes (real-time)
connection.stateStream.listen((state) {
  if (state == BleConnectionState.disconnected) {
    print('Device disconnected!');
  }
});

// Disconnect
await connection.disconnect();

// ── Peripheral: Advertise ──────────────────────────────────
final peripheral = BlePeripheral();

await peripheral.addService(GattServiceDefinition(
  uuid: Guid('180D'),
  characteristics: [
    GattCharacteristicDefinition(
      uuid: Guid('2A37'),
      properties: CharacteristicProperties(notify: true, read: true),
      permissions: CharacteristicPermissions(read: true),
    ),
  ],
));

await peripheral.startAdvertising(AdvertiseSettings(
  localName: 'MyDevice',
  serviceUuids: [Guid('180D')],
));

// Listen for connected centrals
peripheral.onCentralConnected.listen((device) {
  print('Central connected: ${device.id}');
});

// Handle read requests
peripheral.onReadRequest.listen((request) {
  request.respond([0x00, 72]); // Send heart rate data
});

// Send notifications
await peripheral.notifyCharacteristic(
  Guid('180D'), Guid('2A37'), [0x00, 75],
);

// ── L2CAP Channels ─────────────────────────────────────────
// Central side
final channel = await connection.openL2CapChannel(psm, secure: true);
channel.inputStream.listen((data) => print('Received: $data'));
await channel.write([0x01, 0x02, 0x03]);
await channel.close();

// Peripheral side
final psm = await peripheral.publishL2CapChannel(secure: true);
peripheral.onL2CapChannelOpened.listen((channel) {
  channel.inputStream.listen((data) => print('Data: $data'));
});

// ── Background Mode ────────────────────────────────────────
// iOS state restoration
await central.enableBackground(
  iosRestorationIdentifier: 'my_app_central',
);

// Listen for restored devices after app relaunch
central.restoredDevices.listen((devices) {
  print('Restored ${devices.length} devices');
});

// Note: on Windows, enableBackground() activates the runner's tray
// background mode (hide to tray on close instead of terminating).

// ── Platform Capabilities ──────────────────────────────────
// Check what the current platform supports before using features
final caps = central.capabilities;
if (caps.peripheralRole) {
  // Safe to use peripheral features
}
if (caps.l2cap) {
  // Safe to open L2CAP channels
}
```

## BLE Connection Flow

```
┌──────────────┐     scan      ┌──────────────┐
│  BleCentral  │──────────────▶│ BleScanResult│
│              │               │  .device     │
│ startScan()  │               │  .rssi       │
│ stopScan()   │               │  .advData    │
└──────┬───────┘               └──────────────┘
       │ connect(device)
       ▼
┌──────────────┐  discoverServices()  ┌──────────────┐
│BleConnection │─────────────────────▶│  BleService  │
│              │                      │  .uuid       │
│ readChar()   │                      │  .chars[]    │
│ writeChar()  │                      └──────────────┘
│ subscribe()  │
│ readDesc()   │
│ writeDesc()  │
│ requestMtu() │
│ readRssi()   │
│ openL2Cap()  │
│ disconnect() │
└──────────────┘
```

## Setup

### Android

Add permissions to `AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

### iOS

Add to `Info.plist`:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to communicate with BLE devices.</string>
```

For background BLE:
```xml
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-central</string>
  <string>bluetooth-peripheral</string>
</array>
```

### macOS

Add to `macos/Runner/DebugProfile.entitlements` and `Release.entitlements`:
```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```

Add to `macos/Runner/Info.plist`:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to communicate with BLE devices.</string>
```

### Web

Ensure your app is served over **HTTPS** (or localhost). Add service UUIDs to scan filters:
```dart
central.startScan(withServices: [Guid('180D')]); // Required on Web
```

### Linux

Ensure `bluez` is installed:
```bash
sudo apt install bluez
```

### Windows

No additional setup required. Windows 10 or later needed.

## Error Handling

```dart
try {
  await connection.readCharacteristic(char);
} on BleTimeoutError catch (e) {
  // Connection or operation timed out
} on BleGattError catch (e) {
  // GATT operation failed (e.code gives specific reason)
} on BleConnectionError catch (e) {
  // Device disconnected or connection lost
} on BleUnsupportedError catch (e) {
  // Feature not available on this platform
} on BlePermissionError catch (e) {
  // Missing required permissions (e.missingPermissions)
} on BleScanError catch (e) {
  // Scan failed (adapter off, etc.)
}
```

## Configurable Logging

```dart
final central = BleCentral(
  logger: BleLogger(
    level: BleLogLevel.debug,
    onLog: (level, tag, message) {
      // Integrate with your logging framework
      print('[$level][$tag] $message');
    },
  ),
);
```

## Architecture

Single-package Flutter plugin with native platform channels:

```
lib/
├── ble_plus.dart                # Public API exports
└── src/
    ├── ble_central.dart         # Central role (scan, connect)
    ├── ble_connection.dart      # Connected device operations
    ├── ble_peripheral.dart      # Peripheral role (advertise, GATT server)
    ├── ble_l2cap_channel.dart   # L2CAP streaming
    ├── ble_logger.dart          # Configurable logging
    ├── errors/                  # Sealed error types
    ├── models/                  # BleDevice, BleService, etc.
    └── platform/                # Platform interface + implementations
        ├── ble_plus_platform.dart   # Abstract platform interface
        ├── method_channel_ble_plus.dart  # Android/iOS/macOS
        ├── ble_plus_web.dart        # Web Bluetooth API
        ├── ble_plus_linux.dart      # BlueZ D-Bus
        └── ble_plus_windows.dart    # WinRT BLE
android/   # Kotlin (BluetoothGatt, GATT Server, PeripheralManager)
ios/       # Swift (CoreBluetooth Central + Peripheral)
macos/     # Swift (CoreBluetooth Central + Peripheral)
linux/     # C++ (BlueZ GDBus)
windows/   # C++ (WinRT BLE)
```

## Limitations Fixes

`ble_plus` addresses all known limitations :

| Limitation | Fixed in ble_plus |
|--------------------------------|-------------------|
| No peripheral/server role | ✅ Full `BlePeripheral` API |
| No L2CAP channels | ✅ `BleL2CapChannel` |
| Global singleton architecture | ✅ Instance-based `BleCentral`/`BlePeripheral` |
| Generic `PlatformException` errors | ✅ Sealed `BleError` hierarchy |
| No configurable logging | ✅ `BleLogger` with levels + callbacks |
| No connection parameters | ✅ `requestConnectionParameters()` |
| Stream handling issues | ✅ Properly closed streams, reliable `onDone` |
| No descriptor R/W | ✅ `readDescriptor()` / `writeDescriptor()` |
| No MTU change stream | ✅ `connection.mtuStream` |
| No bond/pair management | ✅ `createBond()`, `removeBond()`, `bondState`, `bondStateStream` |
| No real-time connection state | ✅ `isConnected`, `connectionState`, `stateStream` |
| No Web/Linux/Windows | ✅ All 6 platforms supported |
| No macOS (community fork) | ✅ Native CoreBluetooth implementation |
| No background mode architecture | ✅ iOS restoration + Android FGS + Windows tray |
| Hard to test/mock | ✅ Platform interface pattern, DI via logger |
