class MtuChangeEvent {
  final String deviceId;
  final int mtu;
  const MtuChangeEvent({required this.deviceId, required this.mtu});
  factory MtuChangeEvent.fromMap(Map<String, dynamic> map) =>
      MtuChangeEvent(deviceId: map['deviceId'] as String, mtu: map['mtu'] as int);
}

