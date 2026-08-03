import '../platform/types/types.dart';
import 'ble_descriptor.dart';
import 'ble_device.dart';

class BleCharacteristic {
  final Guid uuid;
  final Guid serviceUuid;
  final BleDevice device;
  final CharacteristicProperties properties;
  final List<BleDescriptor> descriptors;
  List<int> lastValue = [];

  BleCharacteristic({
    required this.uuid,
    required this.serviceUuid,
    required this.device,
    required this.properties,
    this.descriptors = const [],
  });

  factory BleCharacteristic.fromData(BleCharacteristicData data, BleDevice device) {
    return BleCharacteristic(
      uuid: Guid(data.uuid),
      serviceUuid: Guid(data.serviceUuid),
      device: device,
      properties: CharacteristicProperties.fromBitmask(data.properties),
      descriptors: data.descriptors.map((d) => BleDescriptor.fromData(d)).toList(),
    );
  }

  @override
  String toString() => 'BleCharacteristic($uuid)';
}

class CharacteristicProperties {
  final bool read;
  final bool write;
  final bool writeWithoutResponse;
  final bool notify;
  final bool indicate;
  final bool authenticatedSignedWrites;
  final bool extendedProperties;

  const CharacteristicProperties({
    this.read = false,
    this.write = false,
    this.writeWithoutResponse = false,
    this.notify = false,
    this.indicate = false,
    this.authenticatedSignedWrites = false,
    this.extendedProperties = false,
  });

  factory CharacteristicProperties.fromBitmask(int bitmask) {
    return CharacteristicProperties(
      read: (bitmask & 0x02) != 0,
      writeWithoutResponse: (bitmask & 0x04) != 0,
      write: (bitmask & 0x08) != 0,
      notify: (bitmask & 0x10) != 0,
      indicate: (bitmask & 0x20) != 0,
      authenticatedSignedWrites: (bitmask & 0x40) != 0,
      extendedProperties: (bitmask & 0x80) != 0,
    );
  }

  int toBitmask() {
    int mask = 0;
    if (read) mask |= 0x02;
    if (writeWithoutResponse) mask |= 0x04;
    if (write) mask |= 0x08;
    if (notify) mask |= 0x10;
    if (indicate) mask |= 0x20;
    if (authenticatedSignedWrites) mask |= 0x40;
    if (extendedProperties) mask |= 0x80;
    return mask;
  }

  @override
  String toString() {
    final parts = <String>[];
    if (read) parts.add('read');
    if (write) parts.add('write');
    if (writeWithoutResponse) parts.add('writeNoResp');
    if (notify) parts.add('notify');
    if (indicate) parts.add('indicate');
    return 'Properties(${parts.join(', ')})';
  }
}

