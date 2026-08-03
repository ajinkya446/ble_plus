import '../platform/types/types.dart';
import 'ble_characteristic.dart';

class GattServiceDefinition {
  final Guid uuid;
  final bool isPrimary;
  final List<GattCharacteristicDefinition> characteristics;

  const GattServiceDefinition({
    required this.uuid,
    this.isPrimary = true,
    required this.characteristics,
  });
}

class GattCharacteristicDefinition {
  final Guid uuid;
  final CharacteristicProperties properties;
  final CharacteristicPermissions permissions;
  final List<int>? initialValue;
  final List<GattDescriptorDefinition> descriptors;

  const GattCharacteristicDefinition({
    required this.uuid,
    required this.properties,
    required this.permissions,
    this.initialValue,
    this.descriptors = const [],
  });
}

class CharacteristicPermissions {
  final bool read;
  final bool write;
  final bool readEncrypted;
  final bool writeEncrypted;

  const CharacteristicPermissions({
    this.read = false,
    this.write = false,
    this.readEncrypted = false,
    this.writeEncrypted = false,
  });

  int toBitmask() {
    int mask = 0;
    if (read) mask |= 0x01;
    if (readEncrypted) mask |= 0x02;
    if (write) mask |= 0x10;
    if (writeEncrypted) mask |= 0x20;
    return mask;
  }
}

class GattDescriptorDefinition {
  final Guid uuid;
  final DescriptorPermissions permissions;
  final List<int>? initialValue;

  const GattDescriptorDefinition({
    required this.uuid,
    required this.permissions,
    this.initialValue,
  });
}

class DescriptorPermissions {
  final bool read;
  final bool write;

  const DescriptorPermissions({this.read = false, this.write = false});

  int toBitmask() {
    int mask = 0;
    if (read) mask |= 0x01;
    if (write) mask |= 0x10;
    return mask;
  }
}

