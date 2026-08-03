# ble_plus

A production-ready Flutter BLE plugin with comprehensive Central and Peripheral APIs, L2CAP channels, background support, and robust error handling across Android, iOS, macOS, Windows, Linux, and Web.

[![pub.dev](https://img.shields.io/pub/v/ble_plus.svg)](https://pub.dev/packages/ble_plus) [![License: BSD-3](https://img.shields.io/badge/license-BSD--3-blue.svg)](LICENSE)

Table of contents
- Features
- Installation
- Platform setup (Android, iOS, macOS, Windows, Linux, Web)
- Quick examples (Central, Peripheral, L2CAP)
- API highlights
- Error handling
- Background operation
- Troubleshooting
- Contributing
- License

Features
- Central: scan, connect, discover services, read/write/subscribe characteristics, descriptors, MTU/RSSI where available
- Peripheral: advertise, GATT server, handle read/write requests, notifications/indications, publish L2CAP channels
- L2CAP: high-throughput streaming on supported platforms (Android 10+, iOS 11+, macOS 10.14+)
- Background: iOS state-restoration, Android foreground-service architecture
- Bond/Pair management and bond state streams
- Instance-based API for testability and dependency injection
- Unified, typed error model (BleError hierarchy)

Installation
1. Add the dependency to your pubspec.yaml:

```yaml
dependencies:
  ble_plus: ^1.0.1
```

2. Run:
```bash
flutter pub get
```

Platform setup

Android
- Min SDK: API 21 (some features require higher API levels)
- Add permissions to AndroidManifest.xml (Android 12+ requires BLUETOOTH_SCAN/CONNECT/ADVERTISE):
```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```
- For advertising on Android 12+, include BLUETOOTH_ADVERTISE and request runtime permissions.

iOS / macOS
- Add to Info.plist:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>This app uses Bluetooth to communicate with BLE devices.</string>
<key>NSBluetoothPeripheralUsageDescription</key>
<string>This app may advertise as a Bluetooth peripheral.</string>
```
- To support background restores on iOS, add UIBackgroundModes with bluetooth-central and bluetooth-peripheral.
- Swift Package Manager: Package.swift files are provided under ios/ble_plus and macos/ble_plus for SPM integration.

Web
- Web supports Central role only via the Web Bluetooth API. Requires HTTPS and user gesture for scanning (device picker on Chrome/Edge).

Linux
- Uses BlueZ D-Bus API. Ensure `bluez` is installed on the host system.

Windows
- Uses WinRT BLE APIs. Requires Windows 10 or later.

Quick examples

Central (scan + connect):
```dart
final central = BleCentral();

central.startScan(withServices: [Guid('180D')]).listen((result) {
  print('Found: ${result.device.displayName} (${result.device.id})');
});

final conn = await central.connect(device);
final services = await conn.discoverServices();
await conn.readCharacteristic(services[0].characteristics[0]);
await conn.disconnect();
```

Peripheral (advertise + GATT server):
```dart
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

await peripheral.startAdvertising(AdvertiseSettings(localName: 'MyDevice', serviceUuids: [Guid('180D')]));
```

L2CAP (high-throughput streaming):
```dart
final channel = await connection.openL2CapChannel(psm, secure: true);
channel.inputStream.listen((data) => print('Received: $data'));
await channel.write([1,2,3]);
await channel.close();
```

API highlights
- BleCentral: startScan(), stopScan(), connect(), capabilities
- BleConnection: discoverServices(), readCharacteristic(), writeCharacteristic(), subscribeToCharacteristic(), readDescriptor(), writeDescriptor(), requestMtu(), readRssi(), openL2CapChannel()
- BlePeripheral: addService(), removeService(), startAdvertising(), stopAdvertising(), onCentralConnected, onReadRequest, notifyCharacteristic(), publishL2CapChannel()
- AdvertiseSettings, GattServiceDefinition, GattCharacteristicDefinition, CharacteristicProperties, CharacteristicPermissions

Error handling
All errors extend BleError for exhaustive handling:
```dart
try {
  await connection.readCharacteristic(char);
} on BleTimeoutError catch (e) {
  // Handle
} on BleGattError catch (e) {
  // e.code available
}
```

Background operation
- iOS: use iosRestorationIdentifier via BleCentral.enableBackground to receive restored devices after app relaunch.
- Android: foreground service approach is required for reliable background scanning/advertising.

Troubleshooting
- Web: scanning opens device picker and requires user gesture + HTTPS.
- Linux: ensure BlueZ is installed and running.
- Android: check runtime permissions for BLUETOOTH_SCAN/CONNECT/ADVERTISE.

Contributing
- Run analyzer and tests:
```bash
flutter analyze
flutter test
```
- Follow the repo's contribution guidelines and add meaningful dartdocs when touching public APIs.

License
BSD-3-Clause. See LICENSE.


