class BleDevice {
  final String id;
  final String? name;
  final String? platformName;

  const BleDevice({required this.id, this.name, this.platformName});

  String get displayName => name ?? platformName ?? id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BleDevice && id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'BleDevice($displayName, $id)';
}

