import '../platform/types/types.dart';

class BleDescriptor {
  final Guid uuid;
  final Guid characteristicUuid;
  final Guid serviceUuid;

  const BleDescriptor({
    required this.uuid,
    required this.characteristicUuid,
    required this.serviceUuid,
  });

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

