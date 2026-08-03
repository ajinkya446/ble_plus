import 'package:ble_plus_platform_interface/ble_plus_platform_interface.dart';

/// Settings for BLE peripheral advertising.
class AdvertiseSettings {
  /// Local name to include in advertisement.
  final String? localName;

  /// Service UUIDs to advertise.
  final List<Guid> serviceUuids;

  /// Manufacturer-specific data (company ID → data bytes).
  final Map<int, List<int>>? manufacturerData;

  /// Transmit power level to include.
  final int? txPowerLevel;

  /// Whether the advertisement should be connectable.
  final bool connectable;

  /// Auto-stop advertising after this duration (Android only).
  final Duration? timeout;

  const AdvertiseSettings({
    this.localName,
    this.serviceUuids = const [],
    this.manufacturerData,
    this.txPowerLevel,
    this.connectable = true,
    this.timeout,
  });
}

