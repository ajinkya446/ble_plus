import 'package:ble_plus_platform_interface/ble_plus_platform_interface.dart';

import 'ble_characteristic.dart';

/// Definition of a GATT service for the local peripheral server.
class GattServiceDefinition {
  /// Service UUID.
  final Guid uuid;

  /// Whether this is a primary service.
  final bool isPrimary;

  /// Characteristics in this service.
  final List<GattCharacteristicDefinition> characteristics;

  const GattServiceDefinition({
    required this.uuid,
    this.isPrimary = true,
    required this.characteristics,
  });
}

/// Definition of a GATT characteristic for the local peripheral server.
class GattCharacteristicDefinition {
  /// Characteristic UUID.
  final Guid uuid;

  /// Properties (read, write, notify, etc.).
  final CharacteristicProperties properties;

  /// Permissions (which operations are allowed).
  final CharacteristicPermissions permissions;

  /// Initial value for this characteristic.
  final List<int>? initialValue;

  /// Descriptors for this characteristic.
  final List<GattDescriptorDefinition> descriptors;

  const GattCharacteristicDefinition({
    required this.uuid,
    required this.properties,
    required this.permissions,
    this.initialValue,
    this.descriptors = const [],
  });
}

/// Permissions for a GATT characteristic.
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

  /// Convert permissions to a bitmask for platform communication.
  int toBitmask() {
    int mask = 0;
    if (read) mask |= 0x01;
    if (readEncrypted) mask |= 0x02;
    if (write) mask |= 0x10;
    if (writeEncrypted) mask |= 0x20;
    return mask;
  }
}

/// Definition of a GATT descriptor for the local peripheral server.
class GattDescriptorDefinition {
  /// Descriptor UUID.
  final Guid uuid;

  /// Permissions.
  final DescriptorPermissions permissions;

  /// Initial value.
  final List<int>? initialValue;

  const GattDescriptorDefinition({
    required this.uuid,
    required this.permissions,
    this.initialValue,
  });
}

/// Permissions for a GATT descriptor.
class DescriptorPermissions {
  final bool read;
  final bool write;

  const DescriptorPermissions({
    this.read = false,
    this.write = false,
  });

  /// Convert to bitmask for platform communication.
  int toBitmask() {
    int mask = 0;
    if (read) mask |= 0x01;
    if (write) mask |= 0x10;
    return mask;
  }
}

