/// Settings for BLE peripheral advertising.
class AdvertiseSettingsData {
  /// Local name to advertise.
  final String? localName;

  /// Service UUIDs to include in advertisement.
  final List<String> serviceUuids;

  /// Manufacturer data (company ID → data bytes).
  final Map<int, List<int>>? manufacturerData;

  /// Transmit power level to include in advertisement.
  final int? txPowerLevel;

  /// Whether the advertisement should be connectable.
  final bool connectable;

  /// Auto-stop advertising after this duration (milliseconds, Android only).
  /// Null means advertise indefinitely.
  final int? timeoutMs;

  const AdvertiseSettingsData({
    this.localName,
    this.serviceUuids = const [],
    this.manufacturerData,
    this.txPowerLevel,
    this.connectable = true,
    this.timeoutMs,
  });

  Map<String, dynamic> toMap() => {
    'localName': localName,
    'serviceUuids': serviceUuids,
    'manufacturerData': manufacturerData?.map(
      (k, v) => MapEntry(k.toString(), v),
    ),
    'txPowerLevel': txPowerLevel,
    'connectable': connectable,
    'timeoutMs': timeoutMs,
  };
}

