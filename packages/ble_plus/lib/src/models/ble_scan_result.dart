import 'package:ble_plus_platform_interface/ble_plus_platform_interface.dart';

import 'ble_device.dart';

/// A scan result from BLE scanning.
class BleScanResult {
  /// The discovered device.
  final BleDevice device;

  /// RSSI at time of discovery.
  final int rssi;

  /// Timestamp of this scan result.
  final DateTime timestamp;

  /// The advertisement data.
  final AdvertisementData advertisementData;

  const BleScanResult({
    required this.device,
    required this.rssi,
    required this.timestamp,
    required this.advertisementData,
  });

  /// Create from platform interface data.
  factory BleScanResult.fromData(BleScanResultData data) {
    return BleScanResult(
      device: BleDevice(id: data.deviceId, name: data.name),
      rssi: data.rssi,
      timestamp: DateTime.fromMillisecondsSinceEpoch(data.timestampMs),
      advertisementData: AdvertisementData(
        localName: data.name,
        connectable: data.connectable,
        serviceUuids: data.serviceUuids.map((s) => Guid(s)).toList(),
        manufacturerData: data.manufacturerData,
        serviceData: data.serviceData.map(
          (k, v) => MapEntry(Guid(k), v),
        ),
        txPowerLevel: data.txPowerLevel,
      ),
    );
  }

  @override
  String toString() =>
      'BleScanResult(${device.displayName}, rssi: $rssi)';
}

/// Parsed advertisement data from a BLE peripheral.
class AdvertisementData {
  /// The local name from the advertisement.
  final String? localName;

  /// Whether the device is connectable.
  final bool connectable;

  /// Transmit power level (if included in advertisement).
  final int? txPowerLevel;

  /// Manufacturer-specific data (company ID → data bytes).
  final Map<int, List<int>> manufacturerData;

  /// Service data (service UUID → data bytes).
  final Map<Guid, List<int>> serviceData;

  /// Service UUIDs advertised.
  final List<Guid> serviceUuids;

  const AdvertisementData({
    this.localName,
    this.connectable = true,
    this.txPowerLevel,
    this.manufacturerData = const {},
    this.serviceData = const {},
    this.serviceUuids = const [],
  });

  @override
  String toString() =>
      'AdvertisementData(name: $localName, services: ${serviceUuids.length})';
}

