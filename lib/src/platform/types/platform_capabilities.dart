class PlatformCapabilities {
  final bool centralRole;
  final bool peripheralRole;
  final bool l2cap;
  final bool backgroundCentral;
  final bool backgroundPeripheral;
  final bool connectionParameters;
  final bool requestMtu;
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
}

