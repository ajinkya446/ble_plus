class BleLogger {
  BleLogLevel level;
  void Function(BleLogLevel level, String tag, String message)? onLog;

  BleLogger({this.level = BleLogLevel.warning, this.onLog});

  void verbose(String tag, String message) => _log(BleLogLevel.verbose, tag, message);
  void debug(String tag, String message) => _log(BleLogLevel.debug, tag, message);
  void info(String tag, String message) => _log(BleLogLevel.info, tag, message);
  void warning(String tag, String message) => _log(BleLogLevel.warning, tag, message);
  void error(String tag, String message) => _log(BleLogLevel.error, tag, message);

  /// Forwards an external log entry (e.g. one emitted by the native plugin and
  /// carried by [BleLogEntry]) respecting the configured [level] and [onLog].
  /// Used to relay the native diagnostic logs (channel "ble_plus/log") to the
  /// same app logger.
  void log(BleLogLevel level, String tag, String message) =>
      _log(level, tag, message);

  void _log(BleLogLevel msgLevel, String tag, String message) {
    if (msgLevel.index >= level.index && onLog != null) {
      onLog!(msgLevel, tag, message);
    }
  }
}

enum BleLogLevel { verbose, debug, info, warning, error, none }

