/// Represents a BLE device (remote or local).
class BleDevice {
  /// Platform-specific device identifier.
  /// On Android: MAC address (e.g., "AA:BB:CC:DD:EE:FF").
  /// On iOS/macOS: UUID string assigned by CoreBluetooth.
  final String id;

  /// Local name from the advertisement data or GAP service.
  final String? name;

  /// Name from the platform's device cache (may differ from advertisement name).
  final String? platformName;

  const BleDevice({
    required this.id,
    this.name,
    this.platformName,
  });

  /// A display-friendly name for the device.
  String get displayName => name ?? platformName ?? id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BleDevice && runtimeType == other.runtimeType && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'BleDevice($displayName, $id)';
}

