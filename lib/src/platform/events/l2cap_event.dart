class L2CapDataEvent {
  final int channelId;
  final List<int> data;
  const L2CapDataEvent({required this.channelId, required this.data});
  factory L2CapDataEvent.fromMap(Map<String, dynamic> map) =>
      L2CapDataEvent(channelId: map['channelId'] as int, data: (map['data'] as List<dynamic>).cast<int>());
}

class L2CapCloseEvent {
  final int channelId;
  final String? reason;
  const L2CapCloseEvent({required this.channelId, this.reason});
  factory L2CapCloseEvent.fromMap(Map<String, dynamic> map) =>
      L2CapCloseEvent(channelId: map['channelId'] as int, reason: map['reason'] as String?);
}

class L2CapChannelOpenedEvent {
  final int channelId;
  final int psm;
  final String deviceId;
  const L2CapChannelOpenedEvent({required this.channelId, required this.psm, required this.deviceId});
  factory L2CapChannelOpenedEvent.fromMap(Map<String, dynamic> map) =>
      L2CapChannelOpenedEvent(channelId: map['channelId'] as int, psm: map['psm'] as int, deviceId: map['deviceId'] as String);
}

