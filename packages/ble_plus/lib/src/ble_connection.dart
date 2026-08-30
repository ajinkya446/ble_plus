import 'dart:async';

import 'package:ble_plus_platform_interface/ble_plus_platform_interface.dart';

import 'ble_l2cap_channel.dart';
import 'ble_logger.dart';
import 'errors/ble_errors.dart';
import 'models/models.dart';

/// Represents an active BLE connection to a peripheral device.
///
/// Obtained via [BleCentral.connect]. All operations on a connected device
/// are performed through this object.
///
/// ```dart
/// final connection = await central.connect(device);
/// final services = await connection.discoverServices();
/// final value = await connection.readCharacteristic(services.first.characteristics.first);
/// await connection.disconnect();
/// ```
class BleConnection {
  final BleDevice _device;
  final BleLogger _logger;
  List<BleService> _services = [];
  int _mtu = 23; // Default BLE MTU

  BlePlusPlatform get _platform => BlePlusPlatform.instance;

  /// Creates a connection handle. Usually obtained from [BleCentral.connect].
  BleConnection({
    required BleDevice device,
    required BleLogger logger,
  })  : _device = device,
        _logger = logger;

  /// The remote BLE device.
  BleDevice get device => _device;

  /// Current connection state.
  BleConnectionState get state {
    // Derived from the platform stream; simplified for now
    return BleConnectionState.connected;
  }

  /// Stream of connection state changes for this device.
  Stream<BleConnectionState> get stateStream => _platform.connectionEventStream
      .where((event) => event.deviceId == _device.id)
      .map((event) => event.state);

  /// Current bond/pair state of the device.
  Future<BleBondState> get bondState async {
    final state = await _platform.getBondState(_device.id);
    return BleBondState.values[state];
  }

  /// Stream of bond state changes for this device.
  Stream<BleBondState> get bondStateStream => _platform.bondStateStream
      .where((event) => event.deviceId == _device.id)
      .map((event) => event.bondState);

  /// Whether still connected.
  bool get isConnected => state == BleConnectionState.connected;

  /// Current MTU size.
  int get mtu => _mtu;

  /// Stream of MTU changes for this device.
  Stream<int> get mtuStream => _platform.mtuChangeStream
      .where((event) => event.deviceId == _device.id)
      .map((event) {
    _mtu = event.mtu;
    return event.mtu;
  });

  // ─── Service Discovery ───────────────────────────────────

  /// Discover all services on the remote device.
  ///
  /// Returns the list of discovered services with their characteristics
  /// and descriptors. Also caches the result in [services].
  Future<List<BleService>> discoverServices() async {
    _logger.debug('BleConnection', 'discoverServices(${_device.id})');

    final serviceDataList = await _platform.discoverServices(_device.id);
    _services = serviceDataList
        .map((data) => BleService.fromData(data, _device))
        .toList();

    return _services;
  }

  /// Previously discovered services (cached after [discoverServices]).
  List<BleService> get services => List.unmodifiable(_services);

  // ─── Read / Write / Notify ───────────────────────────────

  /// Read the current value of a characteristic.
  Future<List<int>> readCharacteristic(BleCharacteristic characteristic) async {
    _logger.debug('BleConnection', 'read(${characteristic.uuid})');

    return _platform.readCharacteristic(
      _device.id,
      characteristic.serviceUuid.str,
      characteristic.uuid.str,
    );
  }

  /// Write a value to a characteristic.
  ///
  /// [withResponse] - If true, waits for a write acknowledgment (default).
  /// If false, uses write-without-response (faster, no guarantee).
  Future<void> writeCharacteristic(
    BleCharacteristic characteristic,
    List<int> value, {
    bool withResponse = true,
  }) async {
    _logger.debug(
      'BleConnection',
      'write(${characteristic.uuid}, ${value.length} bytes, response: $withResponse)',
    );

    await _platform.writeCharacteristic(
      _device.id,
      characteristic.serviceUuid.str,
      characteristic.uuid.str,
      value,
      withResponse,
    );
  }

  /// Subscribe to notifications/indications on a characteristic.
  ///
  /// Returns a stream of value updates. The stream will emit whenever
  /// the peripheral sends a notification or indication.
  ///
  /// Remember to call [unsubscribeFromCharacteristic] when done.
  Stream<List<int>> subscribeToCharacteristic(
    BleCharacteristic characteristic,
  ) {
    _logger.debug('BleConnection', 'subscribe(${characteristic.uuid})');

    // Enable notifications on the platform side
    _platform.setNotification(
      _device.id,
      characteristic.serviceUuid.str,
      characteristic.uuid.str,
      true,
    );

    // Filter the global characteristic value stream to this specific characteristic
    return _platform.characteristicValueStream
        .where(
          (event) =>
              event.deviceId == _device.id &&
              event.characteristicUuid == characteristic.uuid.str,
        )
        .map((event) => event.value);
  }

  /// Unsubscribe from notifications on a characteristic.
  Future<void> unsubscribeFromCharacteristic(
    BleCharacteristic characteristic,
  ) async {
    _logger.debug('BleConnection', 'unsubscribe(${characteristic.uuid})');

    await _platform.setNotification(
      _device.id,
      characteristic.serviceUuid.str,
      characteristic.uuid.str,
      false,
    );
  }

  /// Read a descriptor value.
  Future<List<int>> readDescriptor(BleDescriptor descriptor) async {
    return _platform.readDescriptor(
      _device.id,
      descriptor.serviceUuid.str,
      descriptor.characteristicUuid.str,
      descriptor.uuid.str,
    );
  }

  /// Write a descriptor value.
  Future<void> writeDescriptor(BleDescriptor descriptor, List<int> value) async {
    await _platform.writeDescriptor(
      _device.id,
      descriptor.serviceUuid.str,
      descriptor.characteristicUuid.str,
      descriptor.uuid.str,
      value,
    );
  }

  // ─── MTU ─────────────────────────────────────────────────

  /// Request a specific MTU size.
  ///
  /// Returns the negotiated MTU (may be different from requested).
  /// On iOS, MTU is negotiated automatically — this returns the current value.
  Future<int> requestMtu(int desiredMtu) async {
    _logger.debug('BleConnection', 'requestMtu($desiredMtu)');
    _mtu = await _platform.requestMtu(_device.id, desiredMtu);
    return _mtu;
  }

  // ─── Connection Parameters ───────────────────────────────

  /// Get current connection parameters (if supported by platform).
  ///
  /// Returns null if the platform doesn't support reading connection parameters.
  Future<BleConnectionParameters?> getConnectionParameters() async {
    final data = await _platform.getConnectionParameters(_device.id);
    if (data == null) return null;
    return BleConnectionParameters.fromData(data);
  }

  /// Request connection parameters.
  ///
  /// On Android: maps to `requestConnectionPriority()`.
  /// On iOS: not supported (returns current parameters read-only).
  /// On other platforms: may throw [BleUnsupportedError].
  Future<BleConnectionParameters?> requestConnectionParameters(
    ConnectionPriority priority,
  ) async {
    if (!_platform.capabilities.connectionParameters) {
      throw const BleUnsupportedError(
        'Connection parameter control is not supported on this platform',
      );
    }

    final data = await _platform.requestConnectionPriority(
      _device.id,
      priority.index,
    );
    if (data == null) return null;
    return BleConnectionParameters.fromData(data);
  }

  // ─── RSSI ────────────────────────────────────────────────

  /// Read the RSSI of the connected device.
  Future<int> readRssi() => _platform.readRssi(_device.id);

  // ─── L2CAP ───────────────────────────────────────────────

  /// Open an L2CAP Connection-Oriented Channel to the remote device.
  ///
  /// [psm] - Protocol/Service Multiplexer value.
  /// [secure] - Whether to use encrypted channel (default: true).
  ///
  /// Throws [BleUnsupportedError] on platforms that don't support L2CAP.
  /// Supported on: iOS 11+, Android 10+ (API 29+), macOS 10.14+.
  Future<BleL2CapChannel> openL2CapChannel(int psm, {bool secure = true}) async {
    if (!_platform.capabilities.l2cap) {
      throw const BleUnsupportedError(
        'L2CAP channels are not supported on this platform',
      );
    }

    _logger.info('BleConnection', 'openL2CapChannel(psm: $psm, secure: $secure)');

    final channelId = await _platform.openL2CapChannel(_device.id, psm, secure);
    return BleL2CapChannel(
      channelId: channelId,
      psm: psm,
      device: _device,
    );
  }

  // ─── Disconnect ──────────────────────────────────────────

  /// Initiate bonding/pairing with the device.
  Future<void> createBond() async {
    _logger.info('BleConnection', 'createBond(${_device.id})');
    await _platform.createBond(_device.id);
  }

  /// Remove the bond with the device.
  Future<void> removeBond() async {
    _logger.info('BleConnection', 'removeBond(${_device.id})');
    await _platform.removeBond(_device.id);
  }

  /// Disconnect from the device and release all resources.
  Future<void> disconnect() async {
    _logger.info('BleConnection', 'disconnect(${_device.id})');
    await _platform.disconnect(_device.id);
    _services = [];
  }
}

/// Connection priority levels for [BleConnection.requestConnectionParameters].
enum ConnectionPriority {
  /// Balanced connection interval (~30ms). Default.
  balanced,

  /// High priority connection (~7.5ms interval). Use for time-critical transfers.
  high,

  /// Low power connection (~100ms interval). Use when latency is not critical.
  lowPower,
}

