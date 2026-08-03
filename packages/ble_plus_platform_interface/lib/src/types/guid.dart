
/// A 128-bit UUID used for BLE services, characteristics, and descriptors.
class Guid {
  final String _uuid;

  /// Create a Guid from a string representation.
  /// Accepts formats: "12345678-1234-1234-1234-123456789abc"
  /// or short forms: "180D" (16-bit), "0000180D" (32-bit)
  Guid(String uuid) : _uuid = _normalize(uuid);

  /// Create from a 16-bit short UUID.
  factory Guid.short(int shortUuid) {
    final hex = shortUuid.toRadixString(16).padLeft(4, '0');
    return Guid('0000$hex-0000-1000-8000-00805f9b34fb');
  }

  static String _normalize(String uuid) {
    final clean = uuid.toLowerCase().replaceAll('-', '').replaceAll(' ', '');
    if (clean.length == 4) {
      // 16-bit UUID
      return '0000$clean-0000-1000-8000-00805f9b34fb';
    } else if (clean.length == 8) {
      // 32-bit UUID
      return '$clean-0000-1000-8000-00805f9b34fb';
    } else if (clean.length == 32) {
      // Full 128-bit UUID without dashes
      return '${clean.substring(0, 8)}-${clean.substring(8, 12)}-'
          '${clean.substring(12, 16)}-${clean.substring(16, 20)}-'
          '${clean.substring(20)}';
    }
    // Already formatted
    return uuid.toLowerCase();
  }

  /// The string representation of this UUID.
  @override
  String toString() => _uuid;

  /// The string representation without dashes.
  String get str => _uuid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Guid &&
          runtimeType == other.runtimeType &&
          _uuid == other._uuid;

  @override
  int get hashCode => _uuid.hashCode;
}

