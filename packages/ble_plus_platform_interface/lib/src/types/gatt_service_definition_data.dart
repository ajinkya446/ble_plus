/// Definition of a GATT service to add to the local GATT server.
class GattServiceDefinitionData {
  final String uuid;
  final bool isPrimary;
  final List<GattCharacteristicDefinitionData> characteristics;

  const GattServiceDefinitionData({
    required this.uuid,
    this.isPrimary = true,
    required this.characteristics,
  });

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'isPrimary': isPrimary,
    'characteristics': characteristics.map((c) => c.toMap()).toList(),
  };
}

/// Definition of a GATT characteristic for the local GATT server.
class GattCharacteristicDefinitionData {
  final String uuid;

  /// Bitmask of properties (read=0x02, writeNoResp=0x04, write=0x08, notify=0x10, indicate=0x20).
  final int properties;

  /// Bitmask of permissions (read=0x01, write=0x10, readEncrypted=0x02, writeEncrypted=0x20).
  final int permissions;

  /// Initial value for the characteristic (optional).
  final List<int>? initialValue;

  /// Descriptors for this characteristic.
  final List<GattDescriptorDefinitionData> descriptors;

  const GattCharacteristicDefinitionData({
    required this.uuid,
    required this.properties,
    required this.permissions,
    this.initialValue,
    this.descriptors = const [],
  });

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'properties': properties,
    'permissions': permissions,
    'initialValue': initialValue,
    'descriptors': descriptors.map((d) => d.toMap()).toList(),
  };
}

/// Definition of a GATT descriptor for the local GATT server.
class GattDescriptorDefinitionData {
  final String uuid;

  /// Bitmask of permissions.
  final int permissions;

  /// Initial value for the descriptor.
  final List<int>? initialValue;

  const GattDescriptorDefinitionData({
    required this.uuid,
    required this.permissions,
    this.initialValue,
  });

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'permissions': permissions,
    'initialValue': initialValue,
  };
}

