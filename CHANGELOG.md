## Unreleased

- **Honest per-platform capabilities**: `PlatformCapabilities` now reports what each platform actually implements.
  - `MethodChannelBlePlus` (Android/iOS/macOS) is platform-aware: `l2cap` is `true` only on iOS/macOS (the Android native plugin has no L2CAP), `requestMtu` only on Android (iOS/macOS auto-negotiate), `bondManagement` only on Android (iOS/macOS auto-manage), and `connectionParameters` is `false` everywhere (no platform implements it — it was never even read-only).
  - `backgroundCentral`/`backgroundPeripheral` are `false` on mobile: the Android foreground service and iOS state restoration were never actually implemented — `enableBackground` was a silent no-op. `BleCentral.enableBackground()` now logs a warning and returns on mobile. Windows keeps its tray background mode (`backgroundCentral: true`).
  - `bondManagement` is now `false` on Windows and Linux (the APIs fell through to base no-ops; Windows' native bond handlers were never wired from the Dart facade).
  - Because `openL2CapChannel`, `publishL2CapChannel` and `requestConnectionParameters` are gated on these flags, unsupported calls now throw a clean `BleUnsupportedError` instead of a confusing native `PlatformException`.
- **Docs**: README, ARCHITECTURE, AGENTS and the library doc updated to a support matrix that matches the code (Android: no L2CAP/descriptors/connection params; iOS/macOS: no connection params; Linux/Windows: no bond).

## 1.0.5 - 2026-08-17

- **Windows background support (tray icon)**: `enableBackground`/`disableBackground` now activate the runner's tray background mode (hide to tray on close via the `ble_plus/runner_background` channel) in the example app. The window is hidden to the tray instead of terminating the process so BLE keeps running.
- **Windows robust GATT service discovery**: `DiscoverServices` now queries `GetGattServicesAsync` first with `BluetoothCacheMode::Cached` (the OS cache populated during connect/GattSession) and falls back to a single `Uncached` attempt only when the cache is empty. This avoids the CRT abort on devices exposing the Generic Attribute Service (0x1801 / Service Changed) and retries transient `Unreachable` status.
- **Windows Service Changed (2A05) guard**: subscribing to Service Changed from the app is now rejected with a clear error, since the OS stack manages it internally and writing its CCCD previously hung the process.
- **Windows structured error propagation**: native failures now surface through `error_mapper.dart` with stage, deviceId, HRESULT, GATT status and protocolError, filling the public `BleError` fields instead of generic `PlatformException`.
- **Windows per-device GATT serialization and timeouts**: reads/writes/discover are serialized per device and awaited with `AwaitWithTimeout` (deterministic timeouts, no blocking UI thread, no leaked `std::future` threads).
- **Windows characteristic cache**: discovered characteristics are cached by device to avoid re-querying the GATT stack by UUID (which could abort on Service Changed); the cache is cleared on disconnect.
- **Example app**: notification stream throttled and structured errors surfaced in the UI.
- **Docs**: README and ARCHITECTURE updated with the Windows background support and the new discovery/error behavior.

## 1.0.4 - 2026-08-05

- Windows plugin: robust GATT discovery and structured error propagation groundwork.
- Version and repository metadata updated in `pubspec.yaml`.

## 1.0.3 - 2026-08-05
- Patch release to prepare the links and documentation improvement

## 1.0.1 - 2026-08-03

- Patch release to prepare for pub.dev scoring improvements.
- Added SPM Package.swift files for iOS/macOS to support Swift Package Manager integration.
- Enabled public_member_api_docs lint and added initial dartdoc stubs across the public API to improve documentation coverage.
- Updated package metadata (homepage, repository, issue tracker) and topics to point to the canonical repository.
- Minor Android build script adjustments to reduce legacy Kotlin warnings.

## 1.0.0

**Initial release** — August 3, 2026

### Central Role (All 6 Platforms)
* Scan for nearby BLE devices with service UUID filters, scan modes, and duplicate filtering
* Connect/disconnect with timeout and auto-reconnect support
* **Real-time connection state tracking** — `isConnected`, `connectionState`, `stateStream`
* Discover services, characteristics, and descriptors
* Read, write (with/without response), and subscribe to characteristic notifications/indications
* Read and write descriptors
* Request MTU size (Android; iOS/macOS auto-negotiate)
* Read RSSI of connected devices
* Connection parameter requests (Android `requestConnectionPriority`)

### Bond / Pair Management
* `createBond()` — initiate pairing (Android explicit, iOS/macOS auto, Linux via BlueZ `Pair()`)
* `removeBond()` — remove pairing (Android via reflection, Linux via `RemoveDevice`)
* `bondState` — query current bond state: `none`, `bonding`, `bonded`
* `bondStateStream` — real-time bond state change events via `BroadcastReceiver` (Android)
* iOS/macOS: Pairing handled automatically by CoreBluetooth when accessing encrypted characteristics

### Peripheral Role (Android, iOS, macOS)
* Advertise as a BLE peripheral with custom local name and service UUIDs
* GATT server: add/remove services with multiple characteristics
* Handle read and write requests from centrals
* Send notifications and indications to subscribed centrals
* Multi-central support (multiple centrals connected simultaneously)
* Subscription change events

### L2CAP Channels (Android 10+, iOS 11+, macOS 10.14+)
* Open L2CAP Connection-Oriented Channels for high-throughput streaming
* Publish L2CAP channels from peripheral side
* Read/write data streams on L2CAP channels

### Background Support
* iOS: CoreBluetooth state restoration via `iosRestorationIdentifier`
* Android: Foreground service support architecture

> ⚠️ **Historical claim only.** These were announced in the 1.0.0-era feature list but never actually implemented in the native code. The API reports `backgroundCentral: false` / `backgroundPeripheral: false` on mobile; only the Windows tray background mode is real (see the Unreleased entry above).

### Error Handling
* Sealed `BleError` hierarchy: `BleConnectionError`, `BleGattError`, `BleTimeoutError`, `BlePermissionError`, `BleScanError`, `BleUnsupportedError`
* Platform error codes propagated from native layer
* `GattErrorCode` enum for typed GATT error handling

### Logging
* Configurable `BleLogger` with levels: verbose, debug, info, warning, error, none
* Custom `onLog` callback for integration with any logging framework

### Platform Support
* **Android** — Full Central + Peripheral via BluetoothGatt / BluetoothGattServer
* **iOS** — Full Central + Peripheral via CoreBluetooth
* **macOS** — Full Central + Peripheral via CoreBluetooth
* **Web** — Central only via Web Bluetooth API (Chrome/Edge, requires HTTPS)
* **Linux** — Central only via BlueZ D-Bus
* **Windows** — Central only via WinRT BLE APIs

### Platform-Specific Limitations
* **Web**: No peripheral role, no L2CAP, no background. Scanning uses device picker (user gesture required). Chrome/Edge only.
* **Linux**: Central role only. No peripheral, L2CAP, or background support. Requires BlueZ.
* **Windows**: Central role only. No peripheral, L2CAP, or background support. Requires Windows 10+.
* **iOS/macOS**: MTU is auto-negotiated (cannot set manually). Connection parameters are read-only.
* **Android**: L2CAP requires API 29+ (Android 10). `BLUETOOTH_ADVERTISE` permission required for peripheral role.

### Architecture
* Instance-based API (no global singletons) — fully testable and mockable
* Federated platform interface via `BlePlusPlatform` with `PlatformCapabilities` feature detection
* Separate event channels per concern: scan, connection, characteristic, peripheral
