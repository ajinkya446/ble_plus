class ScanSettings {
  final List<String>? withServices;
  final int scanMode;
  final bool allowDuplicates;

  const ScanSettings({
    this.withServices,
    this.scanMode = 2,
    this.allowDuplicates = false,
  });

  Map<String, dynamic> toMap() => {
    'withServices': withServices,
    'scanMode': scanMode,
    'allowDuplicates': allowDuplicates,
  };
}

