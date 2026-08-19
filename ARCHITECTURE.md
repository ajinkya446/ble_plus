# ble_plus — Architecture (Current, Single-Package)

> **Status:** Describes the shipped code as of v1.0.5.
> Earlier versions of this document described an abandoned *federated monorepo* design. That plan was dropped in favor of a simpler single-package structure; see [History & Decisions](#history--decisions).

## 1. Overview

`ble_plus` is a **single Flutter plugin package**. The repository root *is* the package, and `example/` is the bundled demo app that depends on it via `path: ../`.

There is no Melos workspace. `melos.yaml` is a leftover that exists only as a comment. The `packages/` directory contains deprecated leftovers from the abandoned federated layout (`packages/ble_plus_android` is explicitly marked "DEPRECATED"); it is excluded from analysis by `analysis_options.yaml` and is **not** live code.

Key properties of the design:

- **Instance-based API, no global singleton.** `BleCentral({BleLogger? logger})`, `BlePeripheral()`. (Note: the doc comment in `lib/ble_plus.dart` still shows a stale `BleCentral.instance`; actual usage is `BleCentral()`.)
- **One platform abstraction** — `BlePlusPlatform` (a `PlatformInterface`) — with a Dart implementation per platform, some backed by native code.
- **Capability flags** (`PlatformCapabilities`) let callers gate features at runtime instead of guessing.
- **Sealed `BleError` hierarchy** for typed error handling across all platforms.

## 2. Repository Structure

```
ble_plus/                          # Package root (name: ble_plus, version: 1.0.5)
├── pubspec.yaml                   # Platform declarations (see §4)
├── analysis_options.yaml          # flutter_lints; excludes packages/**, build/**, native dirs
├── lib/
│   ├── ble_plus.dart              # Barrel export of the public API
│   ├── ble_plus_web.dart          # STUB: "no longer used, see lib/src/ble_peripheral.dart"
│   ├── ble_plus_platform_interface.dart  # STUB: "no longer used" (interface lives in src/platform/)
│   └── src/
│       ├── ble_central.dart       # Central role: scan, connect, background
│       ├── ble_connection.dart    # Per-connection GATT operations
│       ├── ble_peripheral.dart    # Peripheral role: advertise, GATT server
│       ├── ble_l2cap_channel.dart # L2CAP CoC wrapper
│       ├── ble_logger.dart        # Leveled logger with onLog callback
│       ├── errors/
│       │   └── ble_errors.dart    # Sealed BleError hierarchy
│       ├── models/                # BleDevice, BleService, BleCharacteristic, ... (app-facing types)
│       └── platform/
│           ├── ble_plus_platform.dart        # Abstract contract; default instance = MethodChannelBlePlus
│           ├── method_channel_ble_plus.dart  # Android / iOS / macOS implementation
│           ├── ble_plus_web.dart             # Web Bluetooth (dart:js_interop)
│           ├── ble_plus_linux.dart           # Linux facade (dartPluginClass)
│           ├── ble_plus_windows.dart         # Windows Dart facade (dartPluginClass)
│           ├── events/           # Event channel data types (scan, connection, characteristic, bond, l2cap, mtu, peripheral)
│           └── types/            # Shared data types + PlatformCapabilities, Guid, settings
├── android/                       # Kotlin: BlePlusPlugin.kt, PeripheralManager.kt (+ JUnit test)
├── ios/                           # Swift: BlePlusPlugin.swift, CentralManager.swift, PeripheralManager.swift
├── macos/                         # Swift: same trio as ios/
├── windows/                       # C++/WinRT: ble_plus_plugin.* + gtest in windows/test/
├── linux/                         # C (BlueZ D-Bus): ble_plus_plugin.cc + gtest in linux/test/
├── test/                          # Dart unit tests (no device needed)
└── example/                       # Demo app; lib/main.dart (Scan/Advertise/Platform Info tabs)
```

## 3. Public API

Barrel export is `lib/ble_plus.dart`. Main classes:

| Class | Role |
|-------|------|
| `BleCentral` | Scan (`startScan`), connect (`connect`), adapter state, background enable/restore, `capabilities` |
| `BleConnection` | Discover services, read/write characteristics and descriptors, subscribe to notifications, MTU, RSSI, connection params, L2CAP, bond, `stateStream` |
| `BlePeripheral` | Add services, advertise, handle read/write requests, notify, publish L2CAP channels |
| `BleL2capChannel` | `inputStream`, `write`, `close` |
| `BleLogger` | Levels verbose→none, custom `onLog` |
| `BleError` (sealed) | `BleConnectionError`, `BleGattError`, `BleTimeoutError`, `BlePermissionError`, `BleScanError`, `BleUnsupportedError` |

Models live in `lib/src/models/` (e.g. `BleDevice`, `BleService`, `GattServiceDefinition`, `AdvertiseSettings`, `CharacteristicProperties`).

## 4. Platform Abstraction & Registration

`BlePlusPlatform extends PlatformInterface` (`lib/src/platform/ble_plus_platform.dart`) declares the full contract with no-op defaults. The default instance is `MethodChannelBlePlus`.

| Platform | Backing | Registration |
|----------|---------|--------------|
| Android | Kotlin (`android/`) | Native plugin → `MethodChannelBlePlus` |
| iOS | Swift (`ios/Classes/`) | Native plugin → `MethodChannelBlePlus` |
| macOS | Swift (`macos/Classes/`) | Native plugin → `MethodChannelBlePlus` |
| Web | Dart `BlePlusWeb` (JS interop) | `pubspec`: `pluginClass: BlePlusWeb`, `fileName: src/platform/ble_plus_web.dart` |
| Linux | Dart `BlePlusLinux` over method/event channels → C BlueZ plugin | `pubspec`: `dartPluginClass: BlePlusLinux` |
| Windows | Native C++/WinRT (`windows/`) | `pubspec`: `pluginClass: BlePlusPlugin` |

Channel layout (shared names across native platforms):

- `ble_plus/methods` — MethodChannel (all request/response ops)
- `ble_plus/scan` — EventChannel (scan results)
- `ble_plus/connection` — EventChannel (connection state)
- `ble_plus/characteristic` — EventChannel (notification/indication values)
- `ble_plus/peripheral` — EventChannel (peripheral events)
- `ble_plus/bond` — EventChannel (bond state changes)

**Gate features via `central.capabilities` (`PlatformCapabilities`) before use** — e.g. peripheral role, L2CAP, background, connection params, MTU request, bond management.

## 5. Feature Matrix

| Feature | Android | iOS | macOS | Web | Linux | Windows |
|---------|:-------:|:---:|:-----:|:---:|:-----:|:-------:|
| Central: Scan / Connect / GATT R/W / Notify | ✅ | ✅ | ✅ | ✅¹ | ✅ | ✅ |
| Central: Descriptors | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Central: MTU Request | ✅ | Auto | Auto | Auto | ❌ | Auto |
| Central: Read RSSI | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Central: Connection Params | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Peripheral: Advertise / GATT Server / Notify | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| L2CAP Channels | ❌ | ✅² | ✅³ | ❌ | ❌ | ❌ |
| Background Mode | ❌ | ❌ | ❌ | ❌ | ❌ | ✅⁴ |
| Bond / Pair Management | ✅ | Auto | Auto | ❌ | ❌ | ❌ |

> ¹ Web scanning shows a device-picker dialog (user gesture + HTTPS, Chrome/Edge only) and requires service-UUID filters.  
> ² iOS L2CAP requires iOS 11+. ³ macOS 10.14+.  
> ⁴ Windows: `enableBackground`/`disableBackground` activate the runner's tray background mode (hide to tray on close via the `ble_plus/runner_background` channel).

> **Honest status notes** — the ✅/❌ above reflect what the code actually implements today:
> - **Android**: L2CAP, descriptor R/W and connection parameters are **not implemented** in the native plugin (leftover stubs live only in the abandoned `packages/` layout).
> - **iOS/macOS**: connection parameters are **not implemented** (they are not even read-only).
> - **Windows**: the native C++ side has bond handlers, but the Dart facade never calls them, so bonding is a silent no-op.
> - **Linux**: bond methods fall through to base no-ops.

### Platform limitations

- **Web** — central only; no L2CAP/background/descriptors/RSSI; `navigator.bluetooth.requestDevice()` picker; HTTPS required.
- **Linux** — central only; needs BlueZ D-Bus; no L2CAP/peripheral/MTU/RSSI/descriptors/bond.
- **Windows** — central only; Windows 10+; no peripheral/L2CAP/RSSI/descriptors/bond; MTU auto. Background: the app does not suspend when minimized/hidden (tray icon in the example runner), activated via `enableBackground`.
- **iOS/macOS** — MTU auto-negotiated (`requestMtu` returns current value); connection parameters not implemented; bonding auto-managed by the OS; macOS needs the Bluetooth sandbox entitlement.
- **Android** — L2CAP/descriptors/connection parameters not implemented in the native plugin; peripheral role needs `BLUETOOTH_ADVERTISE` (Android 12+); scan needs `BLUETOOTH_SCAN` + `BLUETOOTH_CONNECT` + `ACCESS_FINE_LOCATION`; bond management implemented (`createBond`/`removeBond`/`getBondState`); background mode is **not implemented** (`backgroundCentral: false`, no foreground service — `enableBackground` is a no-op).

## 6. Native Implementation Notes

### Android (`android/`, Kotlin)
- Entry point `BlePlusPlugin.kt` (MethodChannel/EventChannel setup); `PeripheralManager.kt` implements GATT server + advertising.
- Central-side GATT client logic lives in the plugin/Kotlin layer (only one outstanding GATT operation at a time — queue serializes reads/writes).
- **Not implemented in the native plugin**: descriptor R/W, L2CAP (client and server) and connection parameters (`getConnectionParameters`/`requestConnectionPriority` are absent — `capabilities` report them unsupported and the Dart API throws `BleUnsupportedError`).

### iOS / macOS (`ios/Classes/`, `macos/Classes/`, Swift)
- Trio per platform: `BlePlusPlugin.swift` (registration), `CentralManager.swift` (CBCentralManager), `PeripheralManager.swift` (CBPeripheralManager).
- iOS and macOS share the same source layout; CoreBluetooth handles MTU and pairing automatically.
- macOS requires `com.apple.security.device.bluetooth` in both Debug and Release entitlements.

### Windows (`windows/`, C++/WinRT)
- `ble_plus_plugin.cpp` implements WinRT BLE: `BluetoothLEAdvertisementWatcher` (scan), `BluetoothLEDevice` (connect), `GattDeviceService`/`GattCharacteristic` (GATT).
- Requires Visual Studio (C++/WinRT fetched via NuGet/FetchContent, `/await` for coroutines).
- **Robust service discovery**: `GetGattServicesAsync` runs first with `BluetoothCacheMode::Cached` (the OS cache is populated during connect/GattSession) and only falls back to a single `Uncached` attempt when the cache is empty. This avoids aborting the CRT on devices that expose the Generic Attribute Service (0x1801 / Service Changed).
- **Service Changed (2A05)** is managed by the OS stack; subscribing to it from the app is blocked with a clear error (writing its CCCD from the app previously hung the process).
- **Structured errors**: every operation reports failures via `SendError` with structured details (stage, deviceId, HRESULT, GATT status, protocolError) that `mapPlatformException` (`lib/src/errors/error_mapper.dart`) propagates into the public `BleError` hierarchy.
- **Runner background**: the example runner registers the `ble_plus/runner_background` channel; `enableBackground`/`disableBackground` toggle the tray background mode (hide to tray on close). Covered by `example/windows/test/tray_icon_test.cpp`.
- **Native logs**: the `ble_plus/log` EventChannel relays native diagnostics to the Dart `BleLogger`; level filtering happens on the Dart side, and with no subscriber the native sink is `nullptr` (zero overhead in production).

### Linux (`linux/`, C, BlueZ D-Bus)
- `ble_plus_plugin.cc` talks to BlueZ over the system D-Bus (`Adapter1.StartDiscovery`, `Device1.Connect`, GATT proxies) and emits scan/connection events.
- Requires `bluez` installed and D-Bus permissions.

### Web (`lib/src/platform/ble_plus_web.dart`, Dart JS interop)
- Uses `dart:js_interop` bindings over `navigator.bluetooth`; `requestDevice()` shows the picker.
- No peripheral/L2CAP/background — unsupported methods throw `UnsupportedError`.

## 7. Testing

- **Dart unit tests** — `flutter test` at the repo root (`test/`). No device needed.
  - Quirk: tests run with `MethodChannelBlePlus` as the platform, but with no native host any real method call throws `MissingPluginException`. Mock platforms must `extend BlePlusPlatform` and assign `BlePlusPlatform.instance`.
- **Integration test** — `cd example && flutter test integration_test/plugin_integration_test.dart -d <device>` (requires a real device/desktop).
- **Example app** — `cd example && flutter run -d <android-device|ios|chrome|windows|linux|macos>`.
- **Native tests**:
  - Android (JUnit, Mockito): `cd example/android && .\gradlew testDebugUnitTest`
  - Windows (gtest, built with the example via `include_ble_plus_tests`): CTest / Visual Studio
  - Linux (gtest): CMake/CTest

## 8. Known Risks & Constraints

| Area | Notes |
|------|-------|
| Android GATT instability (error 133/8) | Retry logic + per-device operation queue + cleanup on disconnect |
| Stream leaks / dangling subscriptions | Lifecycle-bound streams; `dispose()` on `BleCentral`, `BleConnection`, `BleL2capChannel`; broadcast controllers closed on `stopScan`/`onDone` |
| GATT operation races | Serialize per-connection (Android enforces one outstanding op) |
| Docs vs. reality | `ARCHITECTURE.md`/`AGENTS.md` are authoritative for the current single-package layout; `packages/**` and the older federated docs are dead |
| BLE can't be tested in CI | Integration tests require physical hardware; native builds verify compilation only |

## 9. History & Decisions

The original plan (v1 of this document) was a **federated monorepo**: an app-facing `ble_plus` plus per-platform endorsed packages (`ble_plus_platform_interface`, `ble_plus_android`, `ble_plus_ios`, …) coordinated by Melos. That approach was **abandoned** in favor of a single package:

- One `pubspec.yaml`, one version, one publish target.
- The platform interface, all Dart implementations, and all native code live in the root package.
- Remaining traces of the federated attempt — `melos.yaml`, `packages/`, `lib/ble_plus_web.dart`, `lib/ble_plus_platform_interface.dart` — are leftovers: deprecated, excluded from analysis, and not part of the shipped API. (Note: `lib/ble_plus_windows.dart` is **not** a leftover — the live Windows facade lives in `lib/src/platform/ble_plus_windows.dart` and is wired via `dartPluginClass: BlePlusWindows`.)

What *survived* from the original design largely unchanged:

- **Instance-based API** (`BleCentral()` / `BlePeripheral()`), no global singleton.
- **`BlePlusPlatform` as the single contract** and `PlatformCapabilities` for runtime feature detection.
- **Separate event channels per concern** (scan, connection, characteristic, peripheral, bond).
- **Sealed `BleError` hierarchy**, configurable `BleLogger`, central + peripheral split.

---

*End of Architecture Document*
