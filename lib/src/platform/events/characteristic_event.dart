class CharacteristicValueEvent {
  final String deviceId;
  final String serviceUuid;
  final String characteristicUuid;
  final List<int> value;

  const CharacteristicValueEvent({
    required this.deviceId,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.value,
  });

  factory CharacteristicValueEvent.fromMap(Map<String, dynamic> map) {
    return CharacteristicValueEvent(
      deviceId: map['deviceId'] as String,
      serviceUuid: map['serviceUuid'] as String,
      characteristicUuid: map['characteristicUuid'] as String,
      value: (map['value'] as List<dynamic>).cast<int>(),
    );
  }
}

