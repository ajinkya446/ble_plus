import '../platform/types/types.dart';

class AdvertiseSettings {
  final String? localName;
  final List<Guid> serviceUuids;
  final Map<int, List<int>>? manufacturerData;
  final int? txPowerLevel;
  final bool connectable;
  final Duration? timeout;

  const AdvertiseSettings({
    this.localName,
    this.serviceUuids = const [],
    this.manufacturerData,
    this.txPowerLevel,
    this.connectable = true,
    this.timeout,
  });
}

