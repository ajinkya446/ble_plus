import '../types/ble_bond_state.dart';

class BondStateEvent {
  final String deviceId;
  final BleBondState bondState;

  const BondStateEvent({required this.deviceId, required this.bondState});

  factory BondStateEvent.fromMap(Map<String, dynamic> map) {
    return BondStateEvent(
      deviceId: map['deviceId'] as String,
      bondState: BleBondState.values[map['bondState'] as int? ?? 0],
    );
  }
}

