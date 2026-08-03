class BleConnectionParametersData {
  final double? connectionIntervalMs;
  final int? slaveLatency;
  final int? supervisionTimeoutMs;
  final int? mtu;

  const BleConnectionParametersData({
    this.connectionIntervalMs,
    this.slaveLatency,
    this.supervisionTimeoutMs,
    this.mtu,
  });

  factory BleConnectionParametersData.fromMap(Map<String, dynamic> map) {
    return BleConnectionParametersData(
      connectionIntervalMs: (map['connectionIntervalMs'] as num?)?.toDouble(),
      slaveLatency: map['slaveLatency'] as int?,
      supervisionTimeoutMs: map['supervisionTimeoutMs'] as int?,
      mtu: map['mtu'] as int?,
    );
  }
}

