import 'dart:async';

import 'package:flutter/services.dart';

import 'ble_plus_platform.dart';
import 'types/types.dart';
import 'events/events.dart';

/// Linux BLE implementation using BlueZ via method/event channels.
///
/// Central role only. The native C++ plugin communicates with BlueZ D-Bus API.
/// No peripheral role or L2CAP on Linux.
class BlePlusLinux extends BlePlusPlatform {
  BlePlusLinux();

  static void registerWith() {
    BlePlusPlatform.instance = BlePlusLinux();
  }

  static const _method = MethodChannel('ble_plus/methods');
  static const _scanEvent = EventChannel('ble_plus/scan');
  static const _connectionEvent = EventChannel('ble_plus/connection');
  static const _charEvent = EventChannel('ble_plus/characteristic');

  @override
  PlatformCapabilities get capabilities => const PlatformCapabilities(
        centralRole: true,
        peripheralRole: false,
        l2cap: false,
        backgroundCentral: false,
        backgroundPeripheral: false,
        connectionParameters: false,
        requestMtu: false,
        bondManagement: true,
      );

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

  // ── GATT ─────────────────────────────────────────────────
  @override
  Future<List<BleServiceData>> discoverServices(String deviceId) async {
    final result = await _method
        .invokeMethod<List>('discoverServices', {'deviceId': deviceId});
    return (result ?? [])
        .map((e) =>
            BleServiceData.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  @override
  Future<List<int>> readCharacteristic(
      String deviceId, String serviceUuid, String charUuid) async {
    final result = await _method.invokeMethod<List>('readCharacteristic', {
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'characteristicUuid': charUuid,
    });
    return result?.cast<int>() ?? [];
  }

  @override
  Future<void> writeCharacteristic(String deviceId, String serviceUuid,
      String charUuid, List<int> value, bool withResponse) async {
    await _method.invokeMethod('writeCharacteristic', {
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'characteristicUuid': charUuid,
      'value': value,
      'withResponse': withResponse,
    });
  }

  @override
  Future<void> setNotification(
      String deviceId, String serviceUuid, String charUuid, bool enable) async {
    await _method.invokeMethod('setNotification', {
      'deviceId': deviceId,
      'serviceUuid': serviceUuid,
      'characteristicUuid': charUuid,
      'enable': enable,
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
    final result = await _method
        .invokeMethod<int>('requestMtu', {'deviceId': deviceId, 'mtu': mtu});
    return result ?? 23;
  }

  @override
  Future<int> readRssi(String deviceId) async {
    final result =
        await _method.invokeMethod<int>('readRssi', {'deviceId': deviceId});
    return result ?? 0;
  }

  @override
  Future<void> dispose() async {}
}

