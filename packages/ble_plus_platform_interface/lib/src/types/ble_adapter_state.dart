/// Bluetooth adapter state.
enum BleAdapterState {
  /// State is unknown (initial value before first platform event).
  unknown,

  /// The device does not support Bluetooth Low Energy.
  unsupported,

  /// The app is not authorized to use Bluetooth.
  unauthorized,

  /// Bluetooth is turning on.
  turningOn,

  /// Bluetooth is powered on and available.
  on,

  /// Bluetooth is turning off.
  turningOff,

  /// Bluetooth is powered off.
  off,
}

