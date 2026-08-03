# Changelog

## 1.0.2 - 2026-08-03

- Publish prep: bump version to 1.0.2 and fix package validation errors.
- Added dependency on ble_plus_platform_interface (local path) so platform contracts are available at publish time.
- Minor docs and metadata improvements.

## 1.0.1 - 2026-08-03

- Patch release: metadata and documentation improvements aimed at reaching full pub.dev score.
- Added Swift Package Manager support for iOS and macOS (Package.swift files).
- Enabled public_member_api_docs lint and added initial dartdoc stubs to improve documentation coverage.
- Updated package metadata (homepage, repository, issue tracker) and topics.
- Minor build configuration cleanup for Android Kotlin warnings.

## 1.0.0

- Initial release
- BLE Central role: scan, connect, discover services, read/write/notify characteristics
- BLE Peripheral role: advertise, GATT server, handle read/write requests, send notifications
- Unified error handling with sealed `BleError` hierarchy
- Configurable logging via `BleLogger`
- Platform capabilities API for runtime feature detection
- Android support (API 21+, Kotlin)
- iOS support (iOS 13+, Swift/CoreBluetooth)
- Federated plugin architecture with separate platform packages

