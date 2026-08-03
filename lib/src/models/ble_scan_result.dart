import '../platform/types/types.dart';
import '../platform/events/events.dart';
import 'ble_device.dart';

class BleScanResult {
  final BleDevice device;
  final int rssi;
  final DateTime timestamp;
  final AdvertisementData advertisementData;

  const BleScanResult({
    required this.device,
    required this.rssi,
    required this.timestamp,
    required this.advertisementData,
  });

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
        serviceData: data.serviceData.map((k, v) => MapEntry(Guid(k), v)),
        txPowerLevel: data.txPowerLevel,
      ),
    );
  }

  @override
  String toString() => 'BleScanResult(${device.displayName}, rssi: $rssi)';
}

class AdvertisementData {
  final String? localName;
  final bool connectable;
  final int? txPowerLevel;
  final Map<int, List<int>> manufacturerData;
  final Map<Guid, List<int>> serviceData;
  final List<Guid> serviceUuids;

  const AdvertisementData({
    this.localName,
    this.connectable = true,
    this.txPowerLevel,
    this.manufacturerData = const {},
    this.serviceData = const {},
    this.serviceUuids = const [],
  });
}

