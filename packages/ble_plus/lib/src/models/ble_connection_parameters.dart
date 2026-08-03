import 'package:ble_plus_platform_interface/ble_plus_platform_interface.dart';

/// Connection parameters for an active BLE connection.
class BleConnectionParameters {
  /// Connection interval in milliseconds.
  final double? connectionIntervalMs;

  /// Slave latency (number of connection events peripheral can skip).
  final int? slaveLatency;

  /// Supervision timeout in milliseconds.
  final int? supervisionTimeoutMs;

  /// Current MTU size.
  final int? mtu;

  const BleConnectionParameters({
    this.connectionIntervalMs,
    this.slaveLatency,
    this.supervisionTimeoutMs,
    this.mtu,
  });

  /// Create from platform interface data.
  factory BleConnectionParameters.fromData(BleConnectionParametersData data) {
    return BleConnectionParameters(
      connectionIntervalMs: data.connectionIntervalMs,
      slaveLatency: data.slaveLatency,
      supervisionTimeoutMs: data.supervisionTimeoutMs,
      mtu: data.mtu,
    );
  }

  @override
  String toString() =>
      'BleConnectionParameters(interval: ${connectionIntervalMs}ms, '
      'latency: $slaveLatency, timeout: ${supervisionTimeoutMs}ms, mtu: $mtu)';
}

