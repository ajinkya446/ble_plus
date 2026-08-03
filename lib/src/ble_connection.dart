import 'dart:async';

import 'platform/ble_plus_platform.dart';
import 'platform/types/types.dart';
import 'platform/events/events.dart';
import 'ble_l2cap_channel.dart';
import 'ble_logger.dart';
import 'errors/ble_errors.dart';
import 'models/models.dart';

/// Represents an active BLE connection to a peripheral device.
class BleConnection {
  final BleDevice _device;
  final BleLogger _logger;
  List<BleService> _services = [];
  int _mtu = 23;
  BleConnectionState _state = BleConnectionState.connected;
  StreamSubscription<BleConnectionEvent>? _connectionStateSub;

  BlePlusPlatform get _platform => BlePlusPlatform.instance;

  BleConnection({required BleDevice device, required BleLogger logger})
      : _device = device,
        _logger = logger {
    // Listen for disconnect events to update state
    _connectionStateSub = _platform.connectionEventStream
        .where((e) => e.deviceId == _device.id)
        .listen((e) {
      _state = e.state;
    });
  }

  BleDevice get device => _device;
  int get mtu => _mtu;

  /// Current connection state.
  BleConnectionState get connectionState => _state;

  /// Whether the device is currently connected.
  bool get isConnected => _state == BleConnectionState.connected;

  /// Stream of connection state changes for this device.
  Stream<BleConnectionState> get stateStream => _platform.connectionEventStream
      .where((e) => e.deviceId == _device.id)
      .map((e) => e.state);

  /// Current bond/pair state of the device.
  Future<BleBondState> get bondState async {
    final state = await _platform.getBondState(_device.id);
    return BleBondState.values[state];
  }

  /// Stream of bond state changes for this device.
  Stream<BleBondState> get bondStateStream => _platform.bondStateStream
      .where((e) => e.deviceId == _device.id)
      .map((e) => e.bondState);

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

  Stream<int> get mtuStream => _platform.mtuChangeStream
      .where((e) => e.deviceId == _device.id)
      .map((e) { _mtu = e.mtu; return e.mtu; });

  // ─── Service Discovery ───────────────────────────────────
  Future<List<BleService>> discoverServices() async {
    _logger.debug('BleConnection', 'discoverServices(${_device.id})');
    final data = await _platform.discoverServices(_device.id);
    _services = data.map((d) => BleService.fromData(d, _device)).toList();
    return _services;
  }

  List<BleService> get services => List.unmodifiable(_services);

  // ─── Read / Write / Notify ───────────────────────────────
  Future<List<int>> readCharacteristic(BleCharacteristic characteristic) async {
    _logger.debug('BleConnection', 'read(${characteristic.uuid})');
    return _platform.readCharacteristic(_device.id, characteristic.serviceUuid.str, characteristic.uuid.str);
  }

  Future<void> writeCharacteristic(BleCharacteristic characteristic, List<int> value, {bool withResponse = true}) async {
    _logger.debug('BleConnection', 'write(${characteristic.uuid}, ${value.length} bytes)');
    await _platform.writeCharacteristic(_device.id, characteristic.serviceUuid.str, characteristic.uuid.str, value, withResponse);
  }

  Stream<List<int>> subscribeToCharacteristic(BleCharacteristic characteristic) {
    _logger.debug('BleConnection', 'subscribe(${characteristic.uuid})');
    _platform.setNotification(_device.id, characteristic.serviceUuid.str, characteristic.uuid.str, true);
    return _platform.characteristicValueStream
        .where((e) => e.deviceId == _device.id && e.characteristicUuid == characteristic.uuid.str)
        .map((e) => e.value);
  }

  Future<void> unsubscribeFromCharacteristic(BleCharacteristic characteristic) async {
    await _platform.setNotification(_device.id, characteristic.serviceUuid.str, characteristic.uuid.str, false);
  }

  Future<List<int>> readDescriptor(BleDescriptor descriptor) =>
      _platform.readDescriptor(_device.id, descriptor.serviceUuid.str, descriptor.characteristicUuid.str, descriptor.uuid.str);

  Future<void> writeDescriptor(BleDescriptor descriptor, List<int> value) =>
      _platform.writeDescriptor(_device.id, descriptor.serviceUuid.str, descriptor.characteristicUuid.str, descriptor.uuid.str, value);

  // ─── MTU ─────────────────────────────────────────────────
  Future<int> requestMtu(int desiredMtu) async {
    _mtu = await _platform.requestMtu(_device.id, desiredMtu);
    return _mtu;
  }

  // ─── Connection Parameters ───────────────────────────────
  Future<BleConnectionParameters?> getConnectionParameters() async {
    final data = await _platform.getConnectionParameters(_device.id);
    return data == null ? null : BleConnectionParameters.fromData(data);
  }

  Future<BleConnectionParameters?> requestConnectionParameters(ConnectionPriority priority) async {
    if (!_platform.capabilities.connectionParameters) {
      throw const BleUnsupportedError('Connection parameters not supported on this platform');
    }
    final data = await _platform.requestConnectionPriority(_device.id, priority.index);
    return data == null ? null : BleConnectionParameters.fromData(data);
  }

  // ─── RSSI ────────────────────────────────────────────────
  Future<int> readRssi() => _platform.readRssi(_device.id);

  // ─── L2CAP ───────────────────────────────────────────────
  Future<BleL2CapChannel> openL2CapChannel(int psm, {bool secure = true}) async {
    if (!_platform.capabilities.l2cap) {
      throw const BleUnsupportedError('L2CAP not supported on this platform');
    }
    final channelId = await _platform.openL2CapChannel(_device.id, psm, secure);
    return BleL2CapChannel(channelId: channelId, psm: psm, device: _device);
  }

  // ─── Disconnect ──────────────────────────────────────────
  Future<void> disconnect() async {
    _logger.info('BleConnection', 'disconnect(${_device.id})');
    await _connectionStateSub?.cancel();
    _connectionStateSub = null;
    _state = BleConnectionState.disconnected;
    await _platform.disconnect(_device.id);
    _services = [];
  }
}

enum ConnectionPriority { balanced, high, lowPower }

