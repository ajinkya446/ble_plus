/// Declares what features this platform implementation supports.
/// Platform packages override this to reflect their actual capabilities.
class PlatformCapabilities {
  /// Whether this platform supports BLE Central role.
  final bool centralRole;

  /// Whether this platform supports BLE Peripheral/Server role.
  final bool peripheralRole;

  /// Whether this platform supports L2CAP channels.
  final bool l2cap;

  /// Whether this platform supports background BLE (Central).
  final bool backgroundCentral;

  /// Whether this platform supports background BLE (Peripheral).
  final bool backgroundPeripheral;

  /// Whether this platform supports connection parameter control/read.
  final bool connectionParameters;

  /// Whether this platform supports explicit MTU requests.
  final bool requestMtu;

  /// Whether this platform supports bond/pair management.
  final bool bondManagement;

  const PlatformCapabilities({
    this.centralRole = false,
    this.peripheralRole = false,
    this.l2cap = false,
    this.backgroundCentral = false,
    this.backgroundPeripheral = false,
    this.connectionParameters = false,
    this.requestMtu = false,
    this.bondManagement = false,
  });

  @override
  String toString() => 'PlatformCapabilities('
      'central: $centralRole, peripheral: $peripheralRole, '
      'l2cap: $l2cap, bgCentral: $backgroundCentral, '
      'bgPeripheral: $backgroundPeripheral, '
      'connParams: $connectionParameters, mtu: $requestMtu, '
      'bond: $bondManagement)';
}

