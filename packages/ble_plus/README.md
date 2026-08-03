# ble_plus

A production-ready Flutter BLE plugin supporting **Central** and **Peripheral** roles, L2CAP channels, background operation, and connection parameters.

[![pub.dev](https://img.shields.io/pub/v/ble_plus.svg)](https://pub.dev/packages/ble_plus)
[![License: BSD-3](https://img.shields.io/badge/license-BSD--3-blue.svg)](LICENSE)

## Features

| Feature | Android | iOS | macOS | Windows | Linux | Web |
|---------|---------|-----|-------|---------|-------|-----|
| Central: Scan | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| Central: Connect | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| Central: Read/Write/Notify | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ |
| Peripheral: Advertise | ✅ | ✅ | ✅ | ❌ | ⚠️ | ❌ |
| Peripheral: GATT Server | ✅ | ✅ | ✅ | ❌ | ⚠️ | ❌ |
| L2CAP Channels | ✅ API29+ | ✅ iOS11+ | ✅ | ❌ | ❌ | ❌ |
| Background Support | ✅ FGS | ✅ Restore | ❌ | ❌ | ❌ | ❌ |
| Connection Parameters | ✅ | Read-only | Read-only | ❌ | ❌ | ❌ |

## Quick Start

```dart
import 'package:ble_plus/ble_plus.dart';

// Central role - scan and connect
final central = BleCentral();

central.startScan(withServices: [Guid('180D')]).listen((result) {
  print('Found: ${result.device.displayName} RSSI: ${result.rssi}');
});

final connection = await central.connect(device);
final services = await connection.discoverServices();
final value = await connection.readCharacteristic(services.first.characteristics.first);
await connection.disconnect();

// Peripheral role - advertise and serve
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
```

## Architecture

This is a **federated plugin** consisting of:

- `ble_plus` — App-facing Dart API (this package)
- `ble_plus_platform_interface` — Shared types and abstract interface
- `ble_plus_android` — Android implementation (Kotlin, BluetoothGatt/BluetoothGattServer)
- `ble_plus_ios` — iOS implementation (Swift, CoreBluetooth)
- `ble_plus_macos` — macOS implementation (Swift, CoreBluetooth)
- `ble_plus_windows` — Windows implementation (C++, WinRT)
- `ble_plus_linux` — Linux implementation (C, BlueZ D-Bus)
- `ble_plus_web` — Web implementation (Web Bluetooth API)

## Setup

### Android

Add to `AndroidManifest.xml`:
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
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app uses Bluetooth to advertise as a peripheral.</string>
```

For background support, add to `UIBackgroundModes`:
```xml
<key>UIBackgroundModes</key>
<array>
  <string>bluetooth-central</string>
  <string>bluetooth-peripheral</string>
</array>
```

## Error Handling

All errors extend the sealed `BleError` class for exhaustive pattern matching:

```dart
try {
  await connection.readCharacteristic(char);
} on BleTimeoutError catch (e) {
  // Handle timeout
} on BleGattError catch (e) {
  // Handle GATT failure with e.code
} on BleConnectionError catch (e) {
  // Handle connection lost
} on BleUnsupportedError catch (e) {
  // Feature not supported on this platform
}
```

## Logging

```dart
final central = BleCentral(
  logger: BleLogger(
    level: BleLogLevel.debug,
    onLog: (level, tag, message) => debugPrint('[$tag] $message'),
  ),
);
```

## Platform Capabilities

Check what's supported at runtime:

```dart
final central = BleCentral();
if (central.capabilities.peripheralRole) {
  // Safe to use BlePeripheral
}
if (central.capabilities.l2cap) {
  // Safe to open L2CAP channels
}
```

## License

BSD-3-Clause. See [LICENSE](LICENSE).

