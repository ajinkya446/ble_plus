import 'package:ble_plus_platform_interface/ble_plus_platform_interface.dart';

/// A BLE descriptor on a remote device.
class BleDescriptor {
  /// The UUID of this descriptor.
  final Guid uuid;

  /// The UUID of the characteristic this descriptor belongs to.
  final Guid characteristicUuid;

  /// The UUID of the service this descriptor belongs to.
  final Guid serviceUuid;

  const BleDescriptor({
    required this.uuid,
    required this.characteristicUuid,
    required this.serviceUuid,
  });

  /// Create from platform interface data.
  factory BleDescriptor.fromData(BleDescriptorData data) {
    return BleDescriptor(
      uuid: Guid(data.uuid),
      characteristicUuid: Guid(data.characteristicUuid),
      serviceUuid: Guid(data.serviceUuid),
    );
  }

  @override
  String toString() => 'BleDescriptor($uuid)';
}

