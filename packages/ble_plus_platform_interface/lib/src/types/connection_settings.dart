/// Settings for a BLE connection.
class ConnectionSettings {
  /// Connection timeout in milliseconds.
  final int timeoutMs;

  /// Whether to use autoConnect (Android only).
  /// When true, the connection will be established when the device is in range.
  final bool autoConnect;

  const ConnectionSettings({
    this.timeoutMs = 15000,
    this.autoConnect = false,
  });

  Map<String, dynamic> toMap() => {
    'timeoutMs': timeoutMs,
    'autoConnect': autoConnect,
  };
}

