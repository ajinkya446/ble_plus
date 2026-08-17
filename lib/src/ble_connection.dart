import 'dart:async';

import 'package:flutter/services.dart';

import 'platform/ble_plus_platform.dart';
import 'platform/types/types.dart';
import 'platform/events/events.dart';
import 'ble_l2cap_channel.dart';
import 'ble_logger.dart';
import 'errors/ble_errors.dart';
import 'errors/error_mapper.dart';
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
    try {
      final state = await _platform.getBondState(_device.id);
      return BleBondState.values[state];
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  /// Stream of bond state changes for this device.
  Stream<BleBondState> get bondStateStream => _platform.bondStateStream
      .where((e) => e.deviceId == _device.id)
      .map((e) => e.bondState);

  /// Initiate bonding/pairing with the device.
  Future<void> createBond() async {
    _logger.info('BleConnection', 'createBond(${_device.id})');
    try {
      await _platform.createBond(_device.id);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  /// Remove the bond with the device.
  Future<void> removeBond() async {
    _logger.info('BleConnection', 'removeBond(${_device.id})');
    try {
      await _platform.removeBond(_device.id);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  Stream<int> get mtuStream => _platform.mtuChangeStream
      .where((e) => e.deviceId == _device.id)
      .map((e) {
    _mtu = e.mtu;
    return e.mtu;
  });

  // ─── Service Discovery ───────────────────────────────────
  Future<List<BleService>> discoverServices() async {
    _logger.debug('BleConnection', 'discoverServices(${_device.id})');
    try {
      final data = await _platform.discoverServices(_device.id);
      _services = data.map((d) => BleService.fromData(d, _device)).toList();
      return _services;
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  List<BleService> get services => List.unmodifiable(_services);

  // ─── Read / Write / Notify ───────────────────────────────
  Future<List<int>> readCharacteristic(BleCharacteristic characteristic) async {
    _logger.debug('BleConnection', 'read(${characteristic.uuid})');
    try {
      return await _platform.readCharacteristic(
          _device.id, characteristic.serviceUuid.str, characteristic.uuid.str);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  Future<void> writeCharacteristic(BleCharacteristic characteristic,
      List<int> value,
      {bool withResponse = true}) async {
    _logger.debug('BleConnection', 'write(${characteristic.uuid}, ${value.length} bytes)');
    try {
      await _platform.writeCharacteristic(_device.id, characteristic.serviceUuid.str,
          characteristic.uuid.str, value, withResponse);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  Stream<List<int>> subscribeToCharacteristic(BleCharacteristic characteristic) {
    _logger.debug('BleConnection', 'subscribe(${characteristic.uuid})');
    // Errors from setNotification (e.g. Service Changed 2A05 on Windows) must
    // reach the stream subscriber instead of becoming an unhandled exception.
    // The Future is therefore captured with onError and forwarded to the
    // controller rather than being fire-and-forget.
    final controller = StreamController<List<int>>.broadcast();

    _platform
        .setNotification(_device.id, characteristic.serviceUuid.str,
            characteristic.uuid.str, true)
        .then((_) {}, onError: (Object error) {
      if (!controller.isClosed) {
        controller.addError(mapPlatformException(error));
      }
    });

    final sub = _platform.characteristicValueStream
        .where((e) =>
            e.deviceId == _device.id &&
            e.characteristicUuid == characteristic.uuid.str)
        .map((e) => e.value)
        .listen(
      controller.add,
      onError: controller.addError,
      onDone: controller.close,
    );
    // When the consumer cancels the stream, release the channel subscription.
    controller.onCancel = sub.cancel;

    return controller.stream;
  }

  Future<void> unsubscribeFromCharacteristic(
      BleCharacteristic characteristic) async {
    try {
      await _platform.setNotification(_device.id, characteristic.serviceUuid.str,
          characteristic.uuid.str, false);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  Future<List<int>> readDescriptor(BleDescriptor descriptor) async {
    try {
      return await _platform.readDescriptor(_device.id, descriptor.serviceUuid.str,
          descriptor.characteristicUuid.str, descriptor.uuid.str);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  Future<void> writeDescriptor(BleDescriptor descriptor, List<int> value) async {
    try {
      await _platform.writeDescriptor(_device.id, descriptor.serviceUuid.str,
          descriptor.characteristicUuid.str, descriptor.uuid.str, value);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  // ─── MTU ─────────────────────────────────────────────────
  Future<int> requestMtu(int desiredMtu) async {
    try {
      _mtu = await _platform.requestMtu(_device.id, desiredMtu);
      return _mtu;
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  // ─── Connection Parameters ───────────────────────────────
  Future<BleConnectionParameters?> getConnectionParameters() async {
    try {
      final data = await _platform.getConnectionParameters(_device.id);
      return data == null ? null : BleConnectionParameters.fromData(data);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  Future<BleConnectionParameters?> requestConnectionParameters(
      ConnectionPriority priority) async {
    if (!_platform.capabilities.connectionParameters) {
      throw const BleUnsupportedError(
          'Connection parameters not supported on this platform');
    }
    try {
      final data =
          await _platform.requestConnectionPriority(_device.id, priority.index);
      return data == null ? null : BleConnectionParameters.fromData(data);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  // ─── RSSI ────────────────────────────────────────────────
  Future<int> readRssi() async {
    try {
      return await _platform.readRssi(_device.id);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  // ─── L2CAP ───────────────────────────────────────────────
  Future<BleL2CapChannel> openL2CapChannel(int psm, {bool secure = true}) async {
    if (!_platform.capabilities.l2cap) {
      throw const BleUnsupportedError('L2CAP not supported on this platform');
    }
    try {
      final channelId = await _platform.openL2CapChannel(_device.id, psm, secure);
      return BleL2CapChannel(channelId: channelId, psm: psm, device: _device);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
  }

  // ─── Disconnect ──────────────────────────────────────────
  Future<void> disconnect() async {
    _logger.info('BleConnection', 'disconnect(${_device.id})');
    await _connectionStateSub?.cancel();
    _connectionStateSub = null;
    _state = BleConnectionState.disconnected;
    try {
      await _platform.disconnect(_device.id);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }
    _services = [];
  }
}

enum ConnectionPriority { balanced, high, lowPower }
