class AdvertiseSettingsData {
  final String? localName;
  final List<String> serviceUuids;
  final Map<int, List<int>>? manufacturerData;
  final int? txPowerLevel;
  final bool connectable;
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
    'manufacturerData': manufacturerData,
    'txPowerLevel': txPowerLevel,
    'connectable': connectable,
    'timeoutMs': timeoutMs,
  };
}

