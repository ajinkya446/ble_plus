## 0.0.1

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
