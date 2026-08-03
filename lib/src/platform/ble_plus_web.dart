import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'ble_plus_platform.dart';
import 'types/types.dart';
import 'events/events.dart';

// ═══════════════════════════════════════════════════════════
// Web Bluetooth JS Interop Bindings (experimental API)
// ═══════════════════════════════════════════════════════════

@JS('navigator.bluetooth')
external JSObject? get _bluetooth;

@JS('navigator.bluetooth.requestDevice')
external JSPromise<JSObject> _requestDeviceJs(JSObject options);

extension type _BluetoothDevice(JSObject _) implements JSObject {
  external String get id;
  external String? get name;
  external _BluetoothRemoteGATTServer get gatt;
}

extension type _BluetoothRemoteGATTServer(JSObject _) implements JSObject {
  external bool get connected;
  external JSPromise<_BluetoothRemoteGATTServer> connect();
  external void disconnect();
  @JS('getPrimaryServices')
  external JSPromise<JSArray<_BluetoothRemoteGATTService>> getPrimaryServices();
  @JS('getPrimaryService')
  external JSPromise<_BluetoothRemoteGATTService> getPrimaryService(JSString serviceUuid);
}

extension type _BluetoothRemoteGATTService(JSObject _) implements JSObject {
  external String get uuid;
  @JS('getCharacteristics')
  external JSPromise<JSArray<_BluetoothRemoteGATTCharacteristic>> getCharacteristics();
  @JS('getCharacteristic')
  external JSPromise<_BluetoothRemoteGATTCharacteristic> getCharacteristic(JSString charUuid);
}

extension type _BluetoothRemoteGATTCharacteristic(JSObject _) implements JSObject {
  external String get uuid;
  external _BluetoothCharacteristicProperties get properties;
  external JSPromise<JSDataView> readValue();
  @JS('writeValueWithResponse')
  external JSPromise<JSAny?> writeValueWithResponse(JSArrayBuffer value);
  @JS('writeValueWithoutResponse')
  external JSPromise<JSAny?> writeValueWithoutResponse(JSArrayBuffer value);
  @JS('startNotifications')
  external JSPromise<_BluetoothRemoteGATTCharacteristic> startNotifications();
  @JS('stopNotifications')
  external JSPromise<_BluetoothRemoteGATTCharacteristic> stopNotifications();
  external set oncharacteristicvaluechanged(JSFunction? handler);
  external JSDataView? get value;
}

extension type _BluetoothCharacteristicProperties(JSObject _) implements JSObject {
  external bool get read;
  external bool get write;
  external bool get writeWithoutResponse;
  external bool get notify;
  external bool get indicate;
}

/// Web Bluetooth API implementation of [BlePlusPlatform].
///
/// Limitations:
/// - Central role only (no Peripheral/advertising on Web)
/// - No L2CAP, no background mode
/// - Scanning uses `navigator.bluetooth.requestDevice()` which shows a picker
///   (requires user gesture, HTTPS, and explicit service UUID filters)
/// - Chrome/Edge only (not supported in Firefox/Safari)
class BlePlusWeb extends BlePlusPlatform {
  BlePlusWeb();

  static void registerWith(Registrar registrar) {
    BlePlusPlatform.instance = BlePlusWeb();
  }

  final Map<String, _BluetoothDevice> _devices = {};
  final Map<String, _BluetoothRemoteGATTServer> _gattServers = {};

  final StreamController<BleScanResultData> _scanController =
      StreamController<BleScanResultData>.broadcast();
  final StreamController<BleConnectionEvent> _connectionController =
      StreamController<BleConnectionEvent>.broadcast();
  final StreamController<CharacteristicValueEvent> _characteristicController =
      StreamController<CharacteristicValueEvent>.broadcast();

  @override
  PlatformCapabilities get capabilities => const PlatformCapabilities(
        centralRole: true,
        peripheralRole: false,
        l2cap: false,
        backgroundCentral: false,
        backgroundPeripheral: false,
        connectionParameters: false,
        requestMtu: false,
        bondManagement: false,
      );

  // ── Scanning ─────────────────────────────────────────────
  @override
  Stream<BleScanResultData> startScan(ScanSettings settings) {
    _requestDevice(settings);
    return _scanController.stream;
  }

  Future<void> _requestDevice(ScanSettings settings) async {
    try {
      final bt = _bluetooth;
      if (bt == null) {
        _scanController.addError(
            UnsupportedError('Web Bluetooth API not available'));
        return;
      }

      // Build requestDevice options
      final options = <String, dynamic>{};

      if (settings.withServices != null && settings.withServices!.isNotEmpty) {
        final filters = settings.withServices!
            .map((uuid) => {'services': [uuid]}.jsify())
            .toList();
        options['filters'] = filters.jsify();
      } else {
        options['acceptAllDevices'] = true;
      }

      final jsDevice = await _requestDeviceJs(options.jsify() as JSObject).toDart;
      final device = jsDevice as _BluetoothDevice;

      _devices[device.id] = device;

      _scanController.add(BleScanResultData(
        deviceId: device.id,
        name: device.name,
        rssi: 0,
        timestampMs: DateTime.now().millisecondsSinceEpoch,
        connectable: true,
        serviceUuids: settings.withServices ?? [],
      ));
    } catch (e) {
      _scanController.addError(e);
    }
  }

  @override
  Future<void> stopScan() async {}

  // ── Connection ───────────────────────────────────────────
  @override
  Future<void> connect(String deviceId, ConnectionSettings settings) async {
    final device = _devices[deviceId];
    if (device == null) {
      _connectionController.add(BleConnectionEvent(
        deviceId: deviceId,
        state: BleConnectionState.disconnected,
        errorMessage: 'Device not found. Must scan first.',
      ));
      return;
    }

    try {
      final server = await device.gatt.connect().toDart;
      _gattServers[deviceId] = server;
      _connectionController.add(BleConnectionEvent(
        deviceId: deviceId,
        state: BleConnectionState.connected,
      ));
    } catch (e) {
      _connectionController.add(BleConnectionEvent(
        deviceId: deviceId,
        state: BleConnectionState.disconnected,
        errorMessage: e.toString(),
      ));
    }
  }

  @override
  Future<void> disconnect(String deviceId) async {
    _gattServers[deviceId]?.disconnect();
    _gattServers.remove(deviceId);
    _connectionController.add(BleConnectionEvent(
      deviceId: deviceId,
      state: BleConnectionState.disconnected,
    ));
  }

  @override
  Stream<BleConnectionEvent> get connectionEventStream =>
      _connectionController.stream;

  @override
  Future<List<String>> getConnectedDevices() async =>
      _gattServers.keys.toList();

  // ── GATT ─────────────────────────────────────────────────
  @override
  Future<List<BleServiceData>> discoverServices(String deviceId) async {
    final server = _gattServers[deviceId];
    if (server == null) throw Exception('Not connected to $deviceId');

    final services = await server.getPrimaryServices().toDart;
    final result = <BleServiceData>[];

    for (var i = 0; i < services.length; i++) {
      final service = services[i];
      final serviceUuid = service.uuid;

      final chars = await service.getCharacteristics().toDart;
      final charList = <BleCharacteristicData>[];

      for (var j = 0; j < chars.length; j++) {
        final char = chars[j];
        int props = 0;
        final p = char.properties;
        if (p.read) props |= 0x02;
        if (p.writeWithoutResponse) props |= 0x04;
        if (p.write) props |= 0x08;
        if (p.notify) props |= 0x10;
        if (p.indicate) props |= 0x20;

        charList.add(BleCharacteristicData(
          uuid: char.uuid,
          serviceUuid: serviceUuid,
          properties: props,
        ));
      }

      result.add(BleServiceData(
        uuid: serviceUuid,
        isPrimary: true,
        characteristics: charList,
      ));
    }

    return result;
  }

  @override
  Future<List<int>> readCharacteristic(
      String deviceId, String serviceUuid, String charUuid) async {
    final char = await _getCharacteristic(deviceId, serviceUuid, charUuid);
    final dataView = await char.readValue().toDart;
    final byteData = dataView.toDart;
    return byteData.buffer.asUint8List().toList();
  }

  @override
  Future<void> writeCharacteristic(String deviceId, String serviceUuid,
      String charUuid, List<int> value, bool withResponse) async {
    final char = await _getCharacteristic(deviceId, serviceUuid, charUuid);
    final bytes = Uint8List.fromList(value);
    final buffer = bytes.buffer.toJS;

    if (withResponse) {
      await char.writeValueWithResponse(buffer).toDart;
    } else {
      await char.writeValueWithoutResponse(buffer).toDart;
    }
  }

  @override
  Future<void> setNotification(
      String deviceId, String serviceUuid, String charUuid, bool enable) async {
    final char = await _getCharacteristic(deviceId, serviceUuid, charUuid);
    if (enable) {
      await char.startNotifications().toDart;
      char.oncharacteristicvaluechanged = ((JSAny? event) {
        // The 'this' of the event handler is the characteristic itself
        final dataView = char.value;
        if (dataView == null) return;
        final byteData = dataView.toDart;
        final bytes = byteData.buffer.asUint8List().toList();
        _characteristicController.add(CharacteristicValueEvent(
          deviceId: deviceId,
          serviceUuid: serviceUuid,
          characteristicUuid: charUuid,
          value: bytes,
        ));
      }).toJS;
    } else {
      await char.stopNotifications().toDart;
      char.oncharacteristicvaluechanged = null;
    }
  }

  @override
  Stream<CharacteristicValueEvent> get characteristicValueStream =>
      _characteristicController.stream;

  @override
  Future<int> requestMtu(String deviceId, int mtu) async => 512;

  // ── Unsupported on Web ───────────────────────────────────
  @override
  Future<void> startAdvertising(AdvertiseSettingsData settings) async {
    throw UnsupportedError('Peripheral role not supported on Web');
  }

  @override
  Future<void> addService(GattServiceDefinitionData service) async {
    throw UnsupportedError('Peripheral role not supported on Web');
  }

  // ── Helpers ──────────────────────────────────────────────
  Future<_BluetoothRemoteGATTCharacteristic> _getCharacteristic(
      String deviceId, String serviceUuid, String charUuid) async {
    final server = _gattServers[deviceId];
    if (server == null) throw Exception('Not connected to $deviceId');
    final service = await server.getPrimaryService(serviceUuid.toJS).toDart;
    return await service.getCharacteristic(charUuid.toJS).toDart;
  }

  @override
  Future<void> dispose() async {
    for (final server in _gattServers.values) {
      server.disconnect();
    }
    _gattServers.clear();
    _devices.clear();
    await _scanController.close();
    await _connectionController.close();
    await _characteristicController.close();
  }
}
