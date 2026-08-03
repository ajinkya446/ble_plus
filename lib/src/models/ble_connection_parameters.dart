import '../platform/types/types.dart';

class BleConnectionParameters {
  final double? connectionIntervalMs;
  final int? slaveLatency;
  final int? supervisionTimeoutMs;
  final int? mtu;

  const BleConnectionParameters({
    this.connectionIntervalMs,
    this.slaveLatency,
    this.supervisionTimeoutMs,
    this.mtu,
  });

  factory BleConnectionParameters.fromData(BleConnectionParametersData data) {
    return BleConnectionParameters(
      connectionIntervalMs: data.connectionIntervalMs,
      slaveLatency: data.slaveLatency,
      supervisionTimeoutMs: data.supervisionTimeoutMs,
      mtu: data.mtu,
    );
  }
}

