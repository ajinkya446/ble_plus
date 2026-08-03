/// A scan result event from the platform layer.
class BleScanResultData {
  /// Platform-specific device identifier.
  /// Android: MAC address (e.g., "AA:BB:CC:DD:EE:FF")
  /// iOS/macOS: CBPeripheral UUID (e.g., "12345678-1234-1234-1234-123456789abc")
  final String deviceId;

  /// Device name from advertisement data.
  final String? name;

  /// RSSI value at time of discovery.
  final int rssi;

  /// Timestamp of the scan result (milliseconds since epoch).
  final int timestampMs;

  /// Whether the device is connectable.
  final bool connectable;

  /// Service UUIDs advertised.
  final List<String> serviceUuids;

  /// Manufacturer-specific data (company ID → bytes).
  final Map<int, List<int>> manufacturerData;

  /// Service data (service UUID → bytes).
  final Map<String, List<int>> serviceData;

  /// Transmit power level (if available).
  final int? txPowerLevel;

  const BleScanResultData({
    required this.deviceId,
    this.name,
    required this.rssi,
    required this.timestampMs,
    this.connectable = true,
    this.serviceUuids = const [],
    this.manufacturerData = const {},
    this.serviceData = const {},
    this.txPowerLevel,
  });

  factory BleScanResultData.fromMap(Map<String, dynamic> map) {
    return BleScanResultData(
      deviceId: map['deviceId'] as String,
      name: map['name'] as String?,
      rssi: map['rssi'] as int,
      timestampMs: map['timestampMs'] as int? ?? 0,
      connectable: map['connectable'] as bool? ?? true,
      serviceUuids: (map['serviceUuids'] as List<dynamic>?)
              ?.cast<String>() ??
          [],
      manufacturerData: (map['manufacturerData'] as Map<dynamic, dynamic>?)
              ?.map((k, v) => MapEntry(
                    k is int ? k : int.parse(k.toString()),
                    (v as List<dynamic>).cast<int>(),
                  )) ??
          {},
      serviceData: (map['serviceData'] as Map<dynamic, dynamic>?)
              ?.map((k, v) => MapEntry(
                    k.toString(),
                    (v as List<dynamic>).cast<int>(),
                  )) ??
          {},
      txPowerLevel: map['txPowerLevel'] as int?,
    );
  }
}

