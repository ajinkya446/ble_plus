/// Event when a central connects/disconnects from our peripheral GATT server.
class PeripheralConnectionEvent {
  final String deviceId;
  final bool connected;

  const PeripheralConnectionEvent({
    required this.deviceId,
    required this.connected,
  });

  factory PeripheralConnectionEvent.fromMap(Map<String, dynamic> map) {
    return PeripheralConnectionEvent(
      deviceId: map['deviceId'] as String,
      connected: map['connected'] as bool,
    );
  }
}

/// Read request from a central device.
class ReadRequestEvent {
  final int requestId;
  final String deviceId;
  final String serviceUuid;
  final String characteristicUuid;
  final int offset;

  const ReadRequestEvent({
    required this.requestId,
    required this.deviceId,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.offset,
  });

  factory ReadRequestEvent.fromMap(Map<String, dynamic> map) {
    return ReadRequestEvent(
      requestId: map['requestId'] as int,
      deviceId: map['deviceId'] as String,
      serviceUuid: map['serviceUuid'] as String,
      characteristicUuid: map['characteristicUuid'] as String,
      offset: map['offset'] as int? ?? 0,
    );
  }
}

/// Write request from a central device.
class WriteRequestEvent {
  final int requestId;
  final String deviceId;
  final String serviceUuid;
  final String characteristicUuid;
  final List<int> value;
  final int offset;
  final bool responseNeeded;

  const WriteRequestEvent({
    required this.requestId,
    required this.deviceId,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.value,
    required this.offset,
    required this.responseNeeded,
  });

  factory WriteRequestEvent.fromMap(Map<String, dynamic> map) {
    return WriteRequestEvent(
      requestId: map['requestId'] as int,
      deviceId: map['deviceId'] as String,
      serviceUuid: map['serviceUuid'] as String,
      characteristicUuid: map['characteristicUuid'] as String,
      value: (map['value'] as List<dynamic>).cast<int>(),
      offset: map['offset'] as int? ?? 0,
      responseNeeded: map['responseNeeded'] as bool? ?? true,
    );
  }
}

/// Subscription (notify/indicate) change event.
class SubscriptionChangeEvent {
  final String deviceId;
  final String serviceUuid;
  final String characteristicUuid;
  final bool isSubscribed;

  const SubscriptionChangeEvent({
    required this.deviceId,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.isSubscribed,
  });

  factory SubscriptionChangeEvent.fromMap(Map<String, dynamic> map) {
    return SubscriptionChangeEvent(
      deviceId: map['deviceId'] as String,
      serviceUuid: map['serviceUuid'] as String,
      characteristicUuid: map['characteristicUuid'] as String,
      isSubscribed: map['isSubscribed'] as bool,
    );
  }
}

