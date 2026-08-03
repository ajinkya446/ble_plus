/// A production-ready Flutter BLE plugin with Central and Peripheral support.
library ble_plus;

// Platform interface
export 'src/platform/ble_plus_platform.dart';
export 'src/platform/method_channel_ble_plus.dart';
export 'src/platform/ble_plus_linux.dart';
export 'src/platform/ble_plus_windows.dart';
export 'src/platform/types/types.dart';
export 'src/platform/events/events.dart';

// App-facing API
export 'src/ble_central.dart';
export 'src/ble_peripheral.dart';
export 'src/ble_connection.dart';
export 'src/ble_l2cap_channel.dart';
export 'src/ble_logger.dart';

// Models
export 'src/models/models.dart';

// Errors
export 'src/errors/ble_errors.dart';
