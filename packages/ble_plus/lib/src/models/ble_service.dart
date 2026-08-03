import 'package:ble_plus_platform_interface/ble_plus_platform_interface.dart';

import 'ble_characteristic.dart';
import 'ble_device.dart';

/// A discovered BLE service on a remote device.
class BleService {
  /// The UUID of this service.
  final Guid uuid;

  /// Whether this is a primary service.
  final bool isPrimary;

  /// The characteristics belonging to this service.
  final List<BleCharacteristic> characteristics;

  /// Included (secondary) services.
  final List<BleService> includedServices;

  /// The device this service belongs to.
  final BleDevice device;

  const BleService({
    required this.uuid,
    required this.isPrimary,
    required this.characteristics,
    this.includedServices = const [],
    required this.device,
  });

  /// Create from platform interface data.
  factory BleService.fromData(BleServiceData data, BleDevice device) {
    return BleService(
      uuid: Guid(data.uuid),
      isPrimary: data.isPrimary,
      characteristics: data.characteristics
          .map((c) => BleCharacteristic.fromData(c, device))
          .toList(),
      includedServices: data.includedServices
          .map((s) => BleService.fromData(s, device))
          .toList(),
      device: device,
    );
  }

  @override
  String toString() => 'BleService($uuid, ${characteristics.length} chars)';
}

