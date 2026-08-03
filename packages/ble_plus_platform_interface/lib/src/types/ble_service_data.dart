
/// Raw service data returned from the platform layer.
class BleServiceData {
  final String uuid;
  final bool isPrimary;
  final List<BleCharacteristicData> characteristics;
  final List<BleServiceData> includedServices;

  const BleServiceData({
    required this.uuid,
    required this.isPrimary,
    required this.characteristics,
    this.includedServices = const [],
  });

  factory BleServiceData.fromMap(Map<String, dynamic> map) {
    return BleServiceData(
      uuid: map['uuid'] as String,
      isPrimary: map['isPrimary'] as bool? ?? true,
      characteristics: (map['characteristics'] as List<dynamic>?)
              ?.map(
                (e) =>
                    BleCharacteristicData.fromMap(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
      includedServices: (map['includedServices'] as List<dynamic>?)
              ?.map((e) => BleServiceData.fromMap(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'isPrimary': isPrimary,
    'characteristics': characteristics.map((c) => c.toMap()).toList(),
    'includedServices': includedServices.map((s) => s.toMap()).toList(),
  };
}

/// Raw characteristic data from the platform layer.
class BleCharacteristicData {
  final String uuid;
  final String serviceUuid;
  final int properties; // Bitmask of characteristic properties
  final List<BleDescriptorData> descriptors;

  const BleCharacteristicData({
    required this.uuid,
    required this.serviceUuid,
    required this.properties,
    this.descriptors = const [],
  });

  bool get canRead => (properties & 0x02) != 0;
  bool get canWriteWithResponse => (properties & 0x08) != 0;
  bool get canWriteWithoutResponse => (properties & 0x04) != 0;
  bool get canNotify => (properties & 0x10) != 0;
  bool get canIndicate => (properties & 0x20) != 0;

  factory BleCharacteristicData.fromMap(Map<String, dynamic> map) {
    return BleCharacteristicData(
      uuid: map['uuid'] as String,
      serviceUuid: map['serviceUuid'] as String,
      properties: map['properties'] as int? ?? 0,
      descriptors: (map['descriptors'] as List<dynamic>?)
              ?.map(
                (e) => BleDescriptorData.fromMap(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'serviceUuid': serviceUuid,
    'properties': properties,
    'descriptors': descriptors.map((d) => d.toMap()).toList(),
  };
}

/// Raw descriptor data from the platform layer.
class BleDescriptorData {
  final String uuid;
  final String characteristicUuid;
  final String serviceUuid;

  const BleDescriptorData({
    required this.uuid,
    required this.characteristicUuid,
    required this.serviceUuid,
  });

  factory BleDescriptorData.fromMap(Map<String, dynamic> map) {
    return BleDescriptorData(
      uuid: map['uuid'] as String,
      characteristicUuid: map['characteristicUuid'] as String,
      serviceUuid: map['serviceUuid'] as String,
    );
  }

  Map<String, dynamic> toMap() => {
    'uuid': uuid,
    'characteristicUuid': characteristicUuid,
    'serviceUuid': serviceUuid,
  };
}

