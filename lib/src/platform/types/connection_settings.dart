class ConnectionSettings {
  final int timeoutMs;
  final bool autoConnect;

  const ConnectionSettings({this.timeoutMs = 15000, this.autoConnect = false});

  Map<String, dynamic> toMap() => {
    'timeoutMs': timeoutMs,
    'autoConnect': autoConnect,
  };
}

