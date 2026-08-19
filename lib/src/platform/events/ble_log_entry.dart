import '../../ble_logger.dart';

/// Log entry emitted by the native plugin through the "ble_plus/log" channel
/// (EventChannel registered by the Windows plugin).
///
/// `BlePlusWindows.nativeLogStream` translates it and `BleCentral` forwards it
/// to its `BleLogger`, so the native scan/connect/discover/GATT steps can be
/// seen live in the user's console/app.
class BleLogEntry {
  final BleLogLevel level;
  final String tag;
  final String message;

  const BleLogEntry({
    required this.level,
    required this.tag,
    required this.message,
  });

  factory BleLogEntry.fromMap(Map<String, dynamic> map) {
    // The level arrives as an integer (0=verbose ... 4=error), mirror of the
    // native enum. Clamped in case the native side sent an out-of-range value.
    final level = map['level'] as int? ?? BleLogLevel.info.index;
    return BleLogEntry(
      level: level >= 0 && level < BleLogLevel.values.length
          ? BleLogLevel.values[level]
          : BleLogLevel.info,
      tag: (map['tag'] as String?) ?? '',
      message: (map['message'] as String?) ?? '',
    );
  }
}
