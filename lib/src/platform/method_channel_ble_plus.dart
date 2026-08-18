import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/services.dart';
import '../platform/ble_plus_platform.dart';
import '../platform/types/types.dart';
import '../platform/events/events.dart';

/// Method channel implementation of [BlePlusPlatform] for Android/iOS.
class MethodChannelBlePlus extends BlePlusPlatform {
  static const _method = MethodChannel('ble_plus/methods');
  static const _scanEvent = EventChannel('ble_plus/scan');
  static const _connectionEvent = EventChannel('ble_plus/connection');
  static const _charEvent = EventChannel('ble_plus/characteristic');
  static const _peripheralEvent = EventChannel('ble_plus/peripheral');
  static const _bondEvent = EventChannel('ble_plus/bond');

  /// Register this as the platform instance. Called from native plugin registration.
  static void registerWith() {
    BlePlusPlatform.instance = MethodChannelBlePlus();
  }

  @override
  PlatformCapabilities get capabilities {
    // Android/iOS/macOS share this Dart facade but the native Android plugin
    // does not implement L2CAP, and iOS/macOS cannot request MTU or manage
    // bonding (both auto-negotiated by the OS). Report each honestly.
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    return PlatformCapabilities(
      centralRole: true,
      peripheralRole: true,
      l2cap: !isAndroid,
      backgroundCentral: false,
      backgroundPeripheral: false,
      connectionParameters: false,
      requestMtu: isAndroid,
      bondManagement: isAndroid,
    );
  }

  // ── Adapter ──────────────────────────────────────────────
  @override
  Stream<BleAdapterState> get adapterStateStream =>
      _method.invokeMethod<int>('getAdapterState').asStream().map(
        (v) => BleAdapterState.values[v ?? 0],
      );

  @override
  Future<bool> requestEnable() async {
    return await _method.invokeMethod<bool>('requestEnable') ?? false;
  }

  // ── Scanning ─────────────────────────────────────────────
  @override
  Stream<BleScanResultData> startScan(ScanSettings settings) {
    _method.invokeMethod('startScan', settings.toMap());
    return _scanEvent.receiveBroadcastStream().map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      return BleScanResultData.fromMap(map);
    });
  }

  @override
  Future<void> stopScan() async {
    await _method.invokeMethod('stopScan');
  }

  @override
  Stream<bool> get isScanningStream => const Stream.empty();

  // ── Connection ───────────────────────────────────────────
  @override
  Future<void> connect(String deviceId, ConnectionSettings settings) async {
    await _method.invokeMethod('connect', {
      'deviceId': deviceId,
      ...settings.toMap(),
    });
  }

  @override
  Future<void> disconnect(String deviceId) async {
    await _method.invokeMethod('disconnect', {'deviceId': deviceId});
  }

  Stream<BleConnectionEvent>? _connectionStream;

  @override
  Stream<BleConnectionEvent> get connectionEventStream {
    _connectionStream ??= _connectionEvent
        .receiveBroadcastStream()
        .map((event) {
          final map = Map<String, dynamic>.from(event as Map);
          return BleConnectionEvent.fromMap(map);
        })
        .asBroadcastStream();
    return _connectionStream!;
  }

  @override
  Future<List<String>> getConnectedDevices() async {
    final result = await _method.invokeMethod<List>('getConnectedDevices');
    return result?.cast<String>() ?? [];
  }

  // ── Bond / Pair ──────────────────────────────────────────
  @override
  Future<void> createBond(String deviceId) async {
    await _method.invokeMethod('createBond', {'deviceId': deviceId});
  }

  @override
  Future<void> removeBond(String deviceId) async {
    await _method.invokeMethod('removeBond', {'deviceId': deviceId});
  }

  @override
  Future<int> getBondState(String deviceId) async {
    final result = await _method.invokeMethod<int>('getBondState', {'deviceId': deviceId});
    return result ?? 0;
  }

  Stream<BondStateEvent>? _bondStream;

  @override
  Stream<BondStateEvent> get bondStateStream {
    _bondStream ??= _bondEvent
        .receiveBroadcastStream()
        .map((event) {
          final map = Map<String, dynamic>.from(event as Map);
          return BondStateEvent.fromMap(map);
        })
        .asBroadcastStream();
    return _bondStream!;
  }

  // ── GATT ─────────────────────────────────────────────────
  @override
  Future<List<BleServiceData>> discoverServices(String deviceId) async {
    final result = await _method.invokeMethod<List>('discoverServices', {'deviceId': deviceId});
    return (result ?? []).map((e) => BleServiceData.fromMap(Map<String, dynamic>.from(e as Map))).toList();
  }

  @override
  Future<List<int>> readCharacteristic(String deviceId, String serviceUuid, String charUuid) async {
    final result = await _method.invokeMethod<List>('readCharacteristic', {
      'deviceId': deviceId, 'serviceUuid': serviceUuid, 'characteristicUuid': charUuid,
    });
    return result?.cast<int>() ?? [];
  }

  @override
  Future<void> writeCharacteristic(String deviceId, String serviceUuid, String charUuid, List<int> value, bool withResponse) async {
    await _method.invokeMethod('writeCharacteristic', {
      'deviceId': deviceId, 'serviceUuid': serviceUuid, 'characteristicUuid': charUuid,
      'value': value, 'withResponse': withResponse,
    });
  }

  @override
  Future<void> setNotification(String deviceId, String serviceUuid, String charUuid, bool enable) async {
    await _method.invokeMethod('setNotification', {
      'deviceId': deviceId, 'serviceUuid': serviceUuid, 'characteristicUuid': charUuid, 'enable': enable,
    });
  }

  Stream<CharacteristicValueEvent>? _charStream;

  @override
  Stream<CharacteristicValueEvent> get characteristicValueStream {
    _charStream ??= _charEvent
        .receiveBroadcastStream()
        .map((event) {
          final map = Map<String, dynamic>.from(event as Map);
          return CharacteristicValueEvent.fromMap(map);
        })
        .asBroadcastStream();
    return _charStream!;
  }

  @override
  Future<int> requestMtu(String deviceId, int mtu) async {
    final result = await _method.invokeMethod<int>('requestMtu', {'deviceId': deviceId, 'mtu': mtu});
    return result ?? 23;
  }

  @override
  Future<int> readRssi(String deviceId) async {
    final result = await _method.invokeMethod<int>('readRssi', {'deviceId': deviceId});
    return result ?? 0;
  }

  // ── Peripheral ───────────────────────────────────────────
  @override
  Future<void> startAdvertising(AdvertiseSettingsData settings) async {
    await _method.invokeMethod('startAdvertising', settings.toMap());
  }

  @override
  Future<void> stopAdvertising() async {
    await _method.invokeMethod('stopAdvertising');
  }

  @override
  Future<void> addService(GattServiceDefinitionData service) async {
    await _method.invokeMethod('addService', service.toMap());
  }

  Stream<dynamic>? _peripheralStream;

  Stream<dynamic> get _peripheralBroadcast {
    _peripheralStream ??= _peripheralEvent.receiveBroadcastStream().asBroadcastStream();
    return _peripheralStream!;
  }

  @override
  Stream<PeripheralConnectionEvent> get peripheralConnectionStream =>
      _peripheralBroadcast
          .where((e) => (e as Map)['type'] == 'connection')
          .map((e) => PeripheralConnectionEvent.fromMap(Map<String, dynamic>.from(e as Map)));

  @override
  Stream<ReadRequestEvent> get readRequestStream =>
      _peripheralBroadcast
          .where((e) => (e as Map)['type'] == 'readRequest')
          .map((e) => ReadRequestEvent.fromMap(Map<String, dynamic>.from(e as Map)));

  @override
  Stream<WriteRequestEvent> get writeRequestStream =>
      _peripheralBroadcast
          .where((e) => (e as Map)['type'] == 'writeRequest')
          .map((e) => WriteRequestEvent.fromMap(Map<String, dynamic>.from(e as Map)));

  @override
  Stream<SubscriptionChangeEvent> get subscriptionChangeStream =>
      _peripheralBroadcast
          .where((e) => (e as Map)['type'] == 'subscriptionChange')
          .map((e) => SubscriptionChangeEvent.fromMap(Map<String, dynamic>.from(e as Map)));
}

