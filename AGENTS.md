# AGENTS.md

Single-package Flutter BLE plugin (`ble_plus` v1.0.5). The repo root IS the package; `example/` is the demo app (depends on the root via `path: ../`).

## Gotchas

- **Not a monorepo.** `melos.yaml` is a leftover (Melos was removed); never run melos commands.
- **`packages/` is dead code.** Leftover from an abandoned federated layout and excluded by the analyzer (`analysis_options.yaml` excludes `packages/**`). `packages/ble_plus_android` is marked "DEPRECATED". Never edit `packages/**`; root `lib/` is the only live code.
- **`ARCHITECTURE.md` now documents the real single-package layout** (rewritten for v1.0.4). README.md and `ARCHITECTURE.md` are both current; trust code for details.

## Commands

- `flutter pub get`
- `flutter analyze` (`flutter_lints` v6)
- `flutter test` — Dart unit tests in `test/`, no device needed
- Integration test: `cd example; flutter test integration_test/plugin_integration_test.dart -d <device>`
- Example app: `cd example; flutter run -d <android-device|ios|chrome|windows|linux|macos>`
- Native tests:
  - Android (JUnit): `cd example/android; .\gradlew testDebugUnitTest`
  - Windows (gtest, C++/WinRT, needs Visual Studio): built into the example via `include_ble_plus_tests`; run with CTest. Includes:
    - `ble_plus_test.exe` — plugin (2 tests).
    - `ble_plus_tray_test.exe` — tray icon / runner background (`example/windows/test/tray_icon_test.cpp`, 5 tests): hide on close, restore on double-click, clean icon on exit, close without background destroys the window, disabling background removes the icon.
  - Linux (gtest): CMake/CTest

## Architecture

- Barrel export `lib/ble_plus.dart`. Public API: `BleCentral`, `BlePeripheral`, `BleConnection`, `BleL2capChannel`, `BleLogger`, sealed `BleError` hierarchy.
- Everything routes through `BlePlusPlatform extends PlatformInterface`; the default instance is `MethodChannelBlePlus` (backed by Android/iOS/macOS native code). Web (`BlePlusWeb`) and Linux (`BlePlusLinux`) register from Dart in `lib/src/platform/`; Windows is native C++/WinRT in `windows/`.
- Instance-based API, no global singleton: `BleCentral({BleLogger? logger})`.
- Gate features on `BleCentral.capabilities` (`PlatformCapabilities`) before using peripheral role / L2CAP / background.

## Platform reality

- Peripheral role: Android, iOS, macOS only. L2CAP: iOS 11+ / macOS 10.14+ only — the Android native plugin has **no L2CAP** (leftover stubs only in `packages/`). Background: mobile background mode (foreground service / state restoration) is **NOT implemented** — `MethodChannelBlePlus` reports `backgroundCentral: false`/`backgroundPeripheral: false` and `enableBackground` is a no-op there. Windows reports `backgroundCentral: true` and `enableBackground`/`disableBackground` activate the runner background mode (hide to tray on close via the `ble_plus/runner_background` channel — see `example/windows/runner/win32_window.cpp` and `example/windows/test/tray_icon_test.cpp`).
- `MethodChannelBlePlus` capabilities are platform-aware via `defaultTargetPlatform`: `l2cap: !android`, `requestMtu: android`, `bondManagement: android`, `connectionParameters: false` everywhere. `BleUnsupportedError` surfaces for `openL2CapChannel`/`publishL2CapChannel`/`requestConnectionParameters` where unsupported.
- Android: no descriptor R/W, no L2CAP, no connection params in the native plugin (`BlePlusPlugin.kt`); bond implemented (`createBond`/`removeBond`/`getBondState`).
- iOS/macOS: descriptor R/W and L2CAP implemented; connection params **not implemented** (not even read-only); MTU auto-negotiated; bond OS-managed.
- Web: central only; HTTPS + user gesture; Chrome/Edge only; scanning requires service-UUID filters.
- Linux: central only; requires BlueZ; no L2CAP/peripheral/MTU/RSSI/descriptors/bond.
- Windows: central only; Windows 10+; no peripheral/L2CAP/RSSI/descriptors. Bond: native C++ handlers exist (`ble_plus_plugin.cpp`) but the Dart facade (`ble_plus_windows.dart`) never calls them → silent no-op. Background: the app does not suspend when minimized/hidden (tray icon in the example runner).

## Test quirk

- Dart unit tests run with `MethodChannelBlePlus` as the platform, but with no native host any real method call throws `MissingPluginException`. Mock platforms must `extend BlePlusPlatform` and assign `BlePlusPlatform.instance`.
