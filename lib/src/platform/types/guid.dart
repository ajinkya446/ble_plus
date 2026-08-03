/// A 128-bit UUID used for BLE services, characteristics, and descriptors.
class Guid {
  final String _uuid;

  Guid(String uuid) : _uuid = _normalize(uuid);

  factory Guid.short(int shortUuid) {
    final hex = shortUuid.toRadixString(16).padLeft(4, '0');
    return Guid('0000$hex-0000-1000-8000-00805f9b34fb');
  }

  static String _normalize(String uuid) {
    final clean = uuid.toLowerCase().replaceAll('-', '').replaceAll(' ', '');
    if (clean.length == 4) {
      return '0000$clean-0000-1000-8000-00805f9b34fb';
    } else if (clean.length == 8) {
      return '$clean-0000-1000-8000-00805f9b34fb';
    } else if (clean.length == 32) {
      return '${clean.substring(0, 8)}-${clean.substring(8, 12)}-'
          '${clean.substring(12, 16)}-${clean.substring(16, 20)}-'
          '${clean.substring(20)}';
    }
    return uuid.toLowerCase();
  }

  String get str => _uuid;

  @override
  String toString() => _uuid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Guid && _uuid == other._uuid;

  @override
  int get hashCode => _uuid.hashCode;
}

