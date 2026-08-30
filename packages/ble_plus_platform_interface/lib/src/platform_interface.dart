import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'types/types.dart';
import 'events/events.dart';

/// The interface that platform-specific implementations of ble_plus must implement.
///
/// Platform implementations should extend this class rather than implement it,
/// as new methods may be added in the future. Extending guarantees that
/// the subclass will get the default implementation of new methods.
abstract class BlePlusPlatform extends PlatformInterface {
  BlePlusPlatform() : super(token: _token);

  static final Object _token = Object();

  static BlePlusPlatform _instance = _NoOpBlePlusPlatform();

  /// The default instance of [BlePlusPlatform] to use.
  static BlePlusPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [BlePlusPlatform].
  static set instance(BlePlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Reports what features this platform supports.
  PlatformCapabilities get capabilities => const PlatformCapabilities();

  // ═══════════════════════════════════════════════════════════
  // ADAPTER
  // ═══════════════════════════════════════════════════════════

  /// Stream of Bluetooth adapter state changes.
  Stream<BleAdapterState> get adapterStateStream => const Stream.empty();

  /// Request the user to turn on Bluetooth (Android only).
  Future<bool> requestEnable() {
    throw UnimplementedError('requestEnable() has not been implemented.');
  }

  // ═══════════════════════════════════════════════════════════
  // CENTRAL: SCANNING
  // ═══════════════════════════════════════════════════════════

  /// Start scanning for BLE peripherals.
  Stream<BleScanResultData> startScan(ScanSettings settings) {
    throw UnimplementedError('startScan() has not been implemented.');
  }

  /// Stop the current scan.
  Future<void> stopScan() {
    throw UnimplementedError('stopScan() has not been implemented.');
  }

  /// Stream that emits true when scanning starts, false when it stops.
  Stream<bool> get isScanningStream => const Stream.empty();

  // ═══════════════════════════════════════════════════════════
  // CENTRAL: CONNECTION
  // ═══════════════════════════════════════════════════════════

  /// Connect to a BLE device.
  Future<void> connect(String deviceId, ConnectionSettings settings) {
    throw UnimplementedError('connect() has not been implemented.');
  }

  /// Disconnect from a BLE device.
  Future<void> disconnect(String deviceId) {
    throw UnimplementedError('disconnect() has not been implemented.');
  }

  /// Stream of connection state change events.
  Stream<BleConnectionEvent> get connectionEventStream => const Stream.empty();

  /// Get the current bond state for a device.
  Future<int> getBondState(String deviceId) {
    throw UnimplementedError('getBondState() has not been implemented.');
  }

  /// Stream of bond state changes for a device.
  Stream<BondStateEvent> get bondStateStream => const Stream.empty();

  /// Initiate bonding with a device.
  Future<void> createBond(String deviceId) {
    throw UnimplementedError('createBond() has not been implemented.');
  }

  /// Remove a bond from the device.
  Future<void> removeBond(String deviceId) {
    throw UnimplementedError('removeBond() has not been implemented.');
  }

  /// Get list of currently connected device IDs.
  Future<List<String>> getConnectedDevices() {
    throw UnimplementedError('getConnectedDevices() has not been implemented.');
  }

  // ═══════════════════════════════════════════════════════════
  // CENTRAL: GATT OPERATIONS
  // ═══════════════════════════════════════════════════════════

  /// Discover services on a connected device.
  Future<List<BleServiceData>> discoverServices(String deviceId) {
    throw UnimplementedError('discoverServices() has not been implemented.');
  }

  /// Read a characteristic value.
  Future<List<int>> readCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
  ) {
    throw UnimplementedError('readCharacteristic() has not been implemented.');
  }

  /// Write a characteristic value.
  Future<void> writeCharacteristic(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    List<int> value,
    bool withResponse,
  ) {
    throw UnimplementedError('writeCharacteristic() has not been implemented.');
  }

  /// Enable or disable notifications on a characteristic.
  Future<void> setNotification(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    bool enable,
  ) {
    throw UnimplementedError('setNotification() has not been implemented.');
  }

  /// Stream of characteristic value updates (from notifications/reads).
  Stream<CharacteristicValueEvent> get characteristicValueStream =>
      const Stream.empty();

  /// Read a descriptor value.
  Future<List<int>> readDescriptor(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    String descriptorUuid,
  ) {
    throw UnimplementedError('readDescriptor() has not been implemented.');
  }

  /// Write a descriptor value.
  Future<void> writeDescriptor(
    String deviceId,
    String serviceUuid,
    String characteristicUuid,
    String descriptorUuid,
    List<int> value,
  ) {
    throw UnimplementedError('writeDescriptor() has not been implemented.');
  }

  // ═══════════════════════════════════════════════════════════
  // CENTRAL: MTU
  // ═══════════════════════════════════════════════════════════

  /// Request a specific MTU size. Returns the negotiated MTU.
  Future<int> requestMtu(String deviceId, int mtu) {
    throw UnimplementedError('requestMtu() has not been implemented.');
  }

  /// Stream of MTU change events.
  Stream<MtuChangeEvent> get mtuChangeStream => const Stream.empty();

  // ═══════════════════════════════════════════════════════════
  // CENTRAL: RSSI
  // ═══════════════════════════════════════════════════════════

  /// Read RSSI of a connected device.
  Future<int> readRssi(String deviceId) {
    throw UnimplementedError('readRssi() has not been implemented.');
  }

  // ═══════════════════════════════════════════════════════════
  // CENTRAL: CONNECTION PARAMETERS
  // ═══════════════════════════════════════════════════════════

  /// Get current connection parameters for a device.
  Future<BleConnectionParametersData?> getConnectionParameters(
    String deviceId,
  ) {
    throw UnimplementedError(
      'getConnectionParameters() has not been implemented.',
    );
  }

  /// Request connection priority (Android) or return current params (iOS).
  Future<BleConnectionParametersData?> requestConnectionPriority(
    String deviceId,
    int priority,
  ) {
    throw UnimplementedError(
      'requestConnectionPriority() has not been implemented.',
    );
  }

  // ═══════════════════════════════════════════════════════════
  // CENTRAL: L2CAP
  // ═══════════════════════════════════════════════════════════

  /// Open an L2CAP channel to a connected device.
  /// Returns a channel ID for subsequent operations.
  Future<int> openL2CapChannel(String deviceId, int psm, bool secure) {
    throw UnimplementedError('openL2CapChannel() has not been implemented.');
  }

  /// Close an L2CAP channel.
  Future<void> closeL2CapChannel(int channelId) {
    throw UnimplementedError('closeL2CapChannel() has not been implemented.');
  }

  /// Write data to an L2CAP channel.
  Future<void> writeL2Cap(int channelId, List<int> data) {
    throw UnimplementedError('writeL2Cap() has not been implemented.');
  }

  /// Stream of data received on L2CAP channels.
  Stream<L2CapDataEvent> get l2capDataStream => const Stream.empty();

  /// Stream of L2CAP channel close events.
  Stream<L2CapCloseEvent> get l2capCloseStream => const Stream.empty();

  // ═══════════════════════════════════════════════════════════
  // PERIPHERAL: ADVERTISING
  // ═══════════════════════════════════════════════════════════

  /// Start advertising as a BLE peripheral.
  Future<void> startAdvertising(AdvertiseSettingsData settings) {
    throw UnimplementedError('startAdvertising() has not been implemented.');
  }

  /// Stop advertising.
  Future<void> stopAdvertising() {
    throw UnimplementedError('stopAdvertising() has not been implemented.');
  }

  /// Stream of advertising state changes.
  Stream<bool> get isAdvertisingStream => const Stream.empty();

  // ═══════════════════════════════════════════════════════════
  // PERIPHERAL: GATT SERVER
  // ═══════════════════════════════════════════════════════════

  /// Add a service to the local GATT server.
  Future<void> addService(GattServiceDefinitionData service) {
    throw UnimplementedError('addService() has not been implemented.');
  }

  /// Remove a service from the GATT server.
  Future<void> removeService(String uuid) {
    throw UnimplementedError('removeService() has not been implemented.');
  }

  /// Remove all services from the GATT server.
  Future<void> removeAllServices() {
    throw UnimplementedError('removeAllServices() has not been implemented.');
  }

  /// Send a notification/indication to subscribed centrals.
  Future<void> sendNotification(
    String serviceUuid,
    String characteristicUuid,
    List<int> value,
    String? deviceId,
  ) {
    throw UnimplementedError('sendNotification() has not been implemented.');
  }

  /// Respond to a read request from a central.
  Future<void> respondToReadRequest(int requestId, List<int> value) {
    throw UnimplementedError(
      'respondToReadRequest() has not been implemented.',
    );
  }

  /// Respond to a write request from a central.
  Future<void> respondToWriteRequest(int requestId) {
    throw UnimplementedError(
      'respondToWriteRequest() has not been implemented.',
    );
  }

  /// Respond to a request with an error.
  Future<void> respondWithError(int requestId, int errorCode) {
    throw UnimplementedError('respondWithError() has not been implemented.');
  }

  // ═══════════════════════════════════════════════════════════
  // PERIPHERAL: EVENTS
  // ═══════════════════════════════════════════════════════════

  /// Stream of central devices connecting/disconnecting from our GATT server.
  Stream<PeripheralConnectionEvent> get peripheralConnectionStream =>
      const Stream.empty();

  /// Stream of read requests from centrals.
  Stream<ReadRequestEvent> get readRequestStream => const Stream.empty();

  /// Stream of write requests from centrals.
  Stream<WriteRequestEvent> get writeRequestStream => const Stream.empty();

  /// Stream of subscription (notify/indicate) changes.
  Stream<SubscriptionChangeEvent> get subscriptionChangeStream =>
      const Stream.empty();

  // ═══════════════════════════════════════════════════════════
  // PERIPHERAL: L2CAP SERVER
  // ═══════════════════════════════════════════════════════════

  /// Publish an L2CAP channel for incoming connections. Returns the PSM.
  Future<int> publishL2CapChannel(bool secure) {
    throw UnimplementedError(
      'publishL2CapChannel() has not been implemented.',
    );
  }

  /// Unpublish the L2CAP channel.
  Future<void> unpublishL2CapChannel() {
    throw UnimplementedError(
      'unpublishL2CapChannel() has not been implemented.',
    );
  }

  /// Stream of incoming L2CAP channel connections (server side).
  Stream<L2CapChannelOpenedEvent> get l2capServerChannelStream =>
      const Stream.empty();

  // ═══════════════════════════════════════════════════════════
  // BACKGROUND
  // ═══════════════════════════════════════════════════════════

  /// Enable background BLE operations.
  Future<void> enableBackground(BackgroundSettings settings) {
    throw UnimplementedError('enableBackground() has not been implemented.');
  }

  /// Disable background BLE operations.
  Future<void> disableBackground() {
    throw UnimplementedError('disableBackground() has not been implemented.');
  }

  /// Stream of restored device IDs (iOS state restoration).
  Stream<List<String>> get restoredDeviceIdsStream => const Stream.empty();

  // ═══════════════════════════════════════════════════════════
  // DISPOSE
  // ═══════════════════════════════════════════════════════════

  /// Release all resources held by the platform implementation.
  Future<void> dispose() async {}
}

/// A no-op implementation that throws clear errors.
/// Used as the default before a real platform registers itself.
class _NoOpBlePlusPlatform extends BlePlusPlatform {
  @override
  PlatformCapabilities get capabilities => const PlatformCapabilities();
}

