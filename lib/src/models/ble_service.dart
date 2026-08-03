import '../platform/types/types.dart';
import 'ble_characteristic.dart';
import 'ble_device.dart';

class BleService {
  final Guid uuid;
  final bool isPrimary;
  final List<BleCharacteristic> characteristics;
  final List<BleService> includedServices;
  final BleDevice device;

  const BleService({
    required this.uuid,
    required this.isPrimary,
    required this.characteristics,
    this.includedServices = const [],
    required this.device,
  });

  factory BleService.fromData(BleServiceData data, BleDevice device) {
    return BleService(
      uuid: Guid(data.uuid),
      isPrimary: data.isPrimary,
      characteristics: data.characteristics.map((c) => BleCharacteristic.fromData(c, device)).toList(),
      includedServices: data.includedServices.map((s) => BleService.fromData(s, device)).toList(),
      device: device,
    );
  }

  @override
  String toString() => 'BleService($uuid, ${characteristics.length} chars)';
}

