# Changelog

## 0.1.0

- Initial release
- BLE Central role: scan, connect, discover services, read/write/notify characteristics
- BLE Peripheral role: advertise, GATT server, handle read/write requests, send notifications
- Unified error handling with sealed `BleError` hierarchy
- Configurable logging via `BleLogger`
- Platform capabilities API for runtime feature detection
- Android support (API 21+, Kotlin)
- iOS support (iOS 13+, Swift/CoreBluetooth)
- Federated plugin architecture with separate platform packages

