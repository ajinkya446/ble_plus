/// Configurable logger for ble_plus.
///
/// Set the [level] to control verbosity. Provide a custom [onLog] callback
/// to integrate with your app's logging infrastructure.
///
/// ```dart
/// final logger = BleLogger(
///   level: BleLogLevel.debug,
///   onLog: (level, tag, message) => print('[$tag] $message'),
/// );
/// final central = BleCentral(logger: logger);
/// ```
class BleLogger {
  /// The minimum log level to emit.
  BleLogLevel level;

  /// Custom log handler. If null, logs are discarded.
  void Function(BleLogLevel level, String tag, String message)? onLog;

  BleLogger({
    this.level = BleLogLevel.warning,
    this.onLog,
  });

  void verbose(String tag, String message) => _log(BleLogLevel.verbose, tag, message);
  void debug(String tag, String message) => _log(BleLogLevel.debug, tag, message);
  void info(String tag, String message) => _log(BleLogLevel.info, tag, message);
  void warning(String tag, String message) => _log(BleLogLevel.warning, tag, message);
  void error(String tag, String message) => _log(BleLogLevel.error, tag, message);

  void _log(BleLogLevel msgLevel, String tag, String message) {
    if (msgLevel.index >= level.index && onLog != null) {
      onLog!(msgLevel, tag, message);
    }
  }
}

/// Log verbosity levels.
enum BleLogLevel {
  verbose,
  debug,
  info,
  warning,
  error,
  none,
}

