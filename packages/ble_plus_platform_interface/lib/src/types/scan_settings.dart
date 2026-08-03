/// Settings for a BLE scan operation.
class ScanSettings {
  /// Service UUIDs to filter by (null = no filter).
  final List<String>? withServices;

  /// Scan mode (maps to Android ScanSettings.SCAN_MODE_*).
  /// 0 = lowPower, 1 = balanced, 2 = lowLatency, -1 = opportunistic
  final int scanMode;

  /// Whether to report duplicate advertisements.
  final bool allowDuplicates;

  const ScanSettings({
    this.withServices,
    this.scanMode = 2, // lowLatency by default
    this.allowDuplicates = false,
  });

  Map<String, dynamic> toMap() => {
    'withServices': withServices,
    'scanMode': scanMode,
    'allowDuplicates': allowDuplicates,
  };
}

