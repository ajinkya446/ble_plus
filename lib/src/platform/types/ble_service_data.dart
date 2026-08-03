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
              ?.map((e) => BleCharacteristicData.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
      includedServices: (map['includedServices'] as List<dynamic>?)
              ?.map((e) => BleServiceData.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
    );
  }
}

class BleCharacteristicData {
  final String uuid;
  final String serviceUuid;
  final int properties;
  final List<BleDescriptorData> descriptors;

  const BleCharacteristicData({
    required this.uuid,
    required this.serviceUuid,
    required this.properties,
    this.descriptors = const [],
  });

  factory BleCharacteristicData.fromMap(Map<String, dynamic> map) {
    return BleCharacteristicData(
      uuid: map['uuid'] as String,
      serviceUuid: map['serviceUuid'] as String,
      properties: map['properties'] as int? ?? 0,
      descriptors: (map['descriptors'] as List<dynamic>?)
              ?.map((e) => BleDescriptorData.fromMap(Map<String, dynamic>.from(e as Map)))
              .toList() ??
          [],
    );
  }
}

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
}

