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

class GattCharacteristicDefinitionData {
  final String uuid;
  final int properties;
  final int permissions;
  final List<int>? initialValue;
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

class GattDescriptorDefinitionData {
  final String uuid;
  final int permissions;
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

