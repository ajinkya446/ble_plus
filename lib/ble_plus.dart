/// A production-ready Flutter BLE plugin providing comprehensive Central and Peripheral APIs,
/// L2CAP channel support, and cross-platform integrations.
///
/// This library enables developers to:
/// - Implement BLE Central role for scanning and connecting to peripherals
/// - Implement BLE Peripheral role for advertising and accepting connections
/// - Use L2CAP channels for raw data transmission (iOS/macOS; not Android)
/// - Handle connection parameters and MTU negotiation
///
/// Background mode is only implemented on Windows (tray mode); mobile platforms
/// report `backgroundCentral: false` / `backgroundPeripheral: false`.
///
/// Key classes:
/// - [BleCentral]: Manage scanning and central-role operations
/// - [BlePeripheral]: Manage advertising and peripheral-role operations
/// - [BleConnection]: Handle device connections and GATT operations
/// - [BleL2capChannel]: Manage L2CAP channel communication
///
/// Example usage:
/// ```dart
/// import 'package:ble_plus/ble_plus.dart';
///
/// // Scan for BLE devices
/// final central = BleCentral();
/// central.startScan();
/// ```
library;

// Platform interface
// App-facing API
export 'src/ble_central.dart';
export 'src/ble_connection.dart';
export 'src/ble_l2cap_channel.dart';
export 'src/ble_logger.dart';
export 'src/ble_peripheral.dart';
// Errors
export 'src/errors/ble_errors.dart';
// Models
export 'src/models/models.dart';
export 'src/platform/ble_plus_linux.dart';
export 'src/platform/ble_plus_platform.dart';
export 'src/platform/ble_plus_windows.dart';
export 'src/platform/events/events.dart';
export 'src/platform/method_channel_ble_plus.dart';
export 'src/platform/types/types.dart';
