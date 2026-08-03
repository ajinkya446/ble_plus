class BleScanResultData {
  final String deviceId;
  final String? name;
  final int rssi;
  final int timestampMs;
  final bool connectable;
  final List<String> serviceUuids;
  final Map<int, List<int>> manufacturerData;
  final Map<String, List<int>> serviceData;
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
      serviceUuids: (map['serviceUuids'] as List<dynamic>?)?.cast<String>() ?? [],
      manufacturerData: (map['manufacturerData'] as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k is int ? k : int.parse(k.toString()), (v as List<dynamic>).cast<int>()),
          ) ?? {},
      serviceData: (map['serviceData'] as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), (v as List<dynamic>).cast<int>()),
          ) ?? {},
      txPowerLevel: map['txPowerLevel'] as int?,
    );
  }
}

