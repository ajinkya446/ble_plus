import '../types/ble_connection_state.dart';

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

