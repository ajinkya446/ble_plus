/// Connection parameters data as reported by the platform.
class BleConnectionParametersData {
  /// Connection interval in milliseconds.
  final double? connectionIntervalMs;

  /// Slave latency (number of connection events the peripheral can skip).
  final int? slaveLatency;

  /// Supervision timeout in milliseconds.
  final int? supervisionTimeoutMs;

  /// Current MTU size.
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

  Map<String, dynamic> toMap() => {
    if (connectionIntervalMs != null)
      'connectionIntervalMs': connectionIntervalMs,
    if (slaveLatency != null) 'slaveLatency': slaveLatency,
    if (supervisionTimeoutMs != null)
      'supervisionTimeoutMs': supervisionTimeoutMs,
    if (mtu != null) 'mtu': mtu,
  };

  @override
  String toString() =>
      'BleConnectionParametersData(interval: ${connectionIntervalMs}ms, '
      'latency: $slaveLatency, timeout: ${supervisionTimeoutMs}ms, mtu: $mtu)';
}

