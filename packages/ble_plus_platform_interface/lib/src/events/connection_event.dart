/// Connection state change event from the platform.
class BleConnectionEvent {
  final String deviceId;
  final BleConnectionState state;
  final int? errorCode;
  final String? errorMessage;

  const BleConnectionEvent({
    required this.deviceId,
    required this.state,
    this.errorCode,
    this.errorMessage,
  });

  factory BleConnectionEvent.fromMap(Map<String, dynamic> map) {
    return BleConnectionEvent(
      deviceId: map['deviceId'] as String,
      state: BleConnectionState.values[map['state'] as int],
      errorCode: map['errorCode'] as int?,
      errorMessage: map['errorMessage'] as String?,
    );
  }
}

/// Connection state enum used across platform boundary.
enum BleConnectionState {
  disconnected,
  connecting,
  connected,
  disconnecting,
}

/// Bond state enum used across platform boundary.
enum BleBondState {
  none,
  bonding,
  bonded,
}

