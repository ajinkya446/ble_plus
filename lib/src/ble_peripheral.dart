import 'dart:async';

import 'platform/ble_plus_platform.dart';
import 'platform/types/types.dart';
import 'ble_l2cap_channel.dart';
import 'ble_logger.dart';
import 'errors/ble_errors.dart';
import 'models/models.dart';

/// The BLE Peripheral (Server) role manager.
class BlePeripheral {
  final BleLogger _logger;
  BlePlusPlatform get _platform => BlePlusPlatform.instance;

  BlePeripheral({BleLogger? logger}) : _logger = logger ?? BleLogger();

  // ─── Advertising ─────────────────────────────────────────
  bool _isAdvertising = false;
  bool get isAdvertising => _isAdvertising;
  Stream<bool> get isAdvertisingStream => _platform.isAdvertisingStream;

  Future<void> startAdvertising(AdvertiseSettings settings) async {
    if (!_platform.capabilities.peripheralRole) {
      throw const BleUnsupportedError('Peripheral role not supported on this platform');
    }
    _logger.info('BlePeripheral', 'startAdvertising(name: ${settings.localName})');
    await _platform.startAdvertising(AdvertiseSettingsData(
      localName: settings.localName,
      serviceUuids: settings.serviceUuids.map((g) => g.str).toList(),
      manufacturerData: settings.manufacturerData,
      txPowerLevel: settings.txPowerLevel,
      connectable: settings.connectable,
      timeoutMs: settings.timeout?.inMilliseconds,
    ));
    _isAdvertising = true;
  }

  Future<void> stopAdvertising() async {
    _logger.info('BlePeripheral', 'stopAdvertising()');
    await _platform.stopAdvertising();
    _isAdvertising = false;
  }

  // ─── GATT Server ─────────────────────────────────────────
  Future<void> addService(GattServiceDefinition service) async {
    _logger.debug('BlePeripheral', 'addService(${service.uuid})');
    await _platform.addService(GattServiceDefinitionData(
      uuid: service.uuid.str,
      isPrimary: service.isPrimary,
      characteristics: service.characteristics
          .map((c) => GattCharacteristicDefinitionData(
                uuid: c.uuid.str,
                properties: c.properties.toBitmask(),
                permissions: c.permissions.toBitmask(),
                initialValue: c.initialValue,
                descriptors: c.descriptors
                    .map((d) => GattDescriptorDefinitionData(
                          uuid: d.uuid.str,
                          permissions: d.permissions.toBitmask(),
                          initialValue: d.initialValue,
                        ))
                    .toList(),
              ))
          .toList(),
    ));
  }

  Future<void> removeService(Guid serviceUuid) => _platform.removeService(serviceUuid.str);
  Future<void> removeAllServices() => _platform.removeAllServices();

  // ─── Incoming Events ─────────────────────────────────────
  Stream<BleDevice> get onCentralConnected =>
      _platform.peripheralConnectionStream
          .where((e) => e.connected)
          .map((e) => BleDevice(id: e.deviceId));

  Stream<BleDevice> get onCentralDisconnected =>
      _platform.peripheralConnectionStream
          .where((e) => !e.connected)
          .map((e) => BleDevice(id: e.deviceId));

  Stream<ReadRequest> get onReadRequest => _platform.readRequestStream.map(
        (e) => ReadRequest(
          requestId: e.requestId,
          central: BleDevice(id: e.deviceId),
          serviceUuid: Guid(e.serviceUuid),
          characteristicUuid: Guid(e.characteristicUuid),
          offset: e.offset,
        ),
      );

  Stream<WriteRequest> get onWriteRequest => _platform.writeRequestStream.map(
        (e) => WriteRequest(
          requestId: e.requestId,
          central: BleDevice(id: e.deviceId),
          serviceUuid: Guid(e.serviceUuid),
          characteristicUuid: Guid(e.characteristicUuid),
          value: e.value,
          offset: e.offset,
          responseNeeded: e.responseNeeded,
        ),
      );

  Stream<SubscriptionChange> get onSubscriptionChange =>
      _platform.subscriptionChangeStream.map(
        (e) => SubscriptionChange(
          central: BleDevice(id: e.deviceId),
          serviceUuid: Guid(e.serviceUuid),
          characteristicUuid: Guid(e.characteristicUuid),
          isSubscribed: e.isSubscribed,
        ),
      );

  // ─── Sending Data ────────────────────────────────────────
  Future<void> notifyCharacteristic(
    Guid serviceUuid,
    Guid characteristicUuid,
    List<int> value, {
    BleDevice? toDevice,
  }) async {
    await _platform.sendNotification(serviceUuid.str, characteristicUuid.str, value, toDevice?.id);
  }

  // ─── L2CAP Server ────────────────────────────────────────
  Future<int> publishL2CapChannel({bool secure = true}) async {
    if (!_platform.capabilities.l2cap) {
      throw const BleUnsupportedError('L2CAP not supported on this platform');
    }
    return _platform.publishL2CapChannel(secure);
  }

  Stream<BleL2CapChannel> get onL2CapChannelOpened =>
      _platform.l2capServerChannelStream.map(
        (e) => BleL2CapChannel(channelId: e.channelId, psm: e.psm, device: BleDevice(id: e.deviceId)),
      );

  Future<void> unpublishL2CapChannel() => _platform.unpublishL2CapChannel();

  // ─── Cleanup ─────────────────────────────────────────────
  Future<void> dispose() async {
    if (_isAdvertising) await stopAdvertising();
    await removeAllServices();
  }
}

