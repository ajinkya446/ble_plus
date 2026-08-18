# ble_plus Example

Demonstrates all features of the `ble_plus` plugin across all supported platforms.

## Tabs

### 1. Scan (Central Role)
- Scan for nearby BLE devices with RSSI signal strength indicators
- Connect to a device to discover services and characteristics
- Read, write, and subscribe to characteristic notifications
- Read RSSI of connected devices (Android/iOS/macOS)
- Request high-priority connection parameters (Android)
- Shows Web-specific guidance when running in browser

### 2. Advertise (Peripheral Role)
- Advertise as a BLE Heart Rate Monitor peripheral
- GATT server with Heart Rate Service (0x180D)
- Handle incoming read/write requests from centrals
- Send heart rate notifications to subscribed centrals
- Event log showing all peripheral activity
- **Shows "Not Supported" message on Web, Linux, and Windows** (Central only platforms)

### 3. Platform Info
- Shows current platform name and all `PlatformCapabilities` flags
- Displays platform-specific limitations:
  - **Android**: Permission requirements, L2CAP API level
  - **iOS**: Auto-negotiated MTU, connection parameters not implemented
  - **macOS**: Bluetooth entitlement, no background
  - **Web**: Device picker, HTTPS requirement, Chrome/Edge only
  - **Linux**: BlueZ requirement, Central only
  - **Windows**: Windows 10+ requirement, Central only

## Running

```bash
# Android
flutter run -d <android-device>

# iOS
cd ios && pod install && cd ..
flutter run -d <ios-device>

# macOS
flutter run -d macos

# Web (Chrome)
flutter run -d chrome

# Linux
flutter run -d linux

# Windows
flutter run -d windows
```

## Error Handling Demo

The example demonstrates all `BleError` subtypes:
- `BleTimeoutError` — connection timeout
- `BleConnectionError` — connection failure with platform error codes
- `BleUnsupportedError` — feature not available (e.g., RSSI on Web)
- `BleGattError` — GATT operation failures
- `BleError` — catch-all for any BLE error
