import 'dart:async';

import 'package:ble_plus_platform_interface/ble_plus_platform_interface.dart';

import 'ble_l2cap_channel.dart';
import 'ble_logger.dart';
import 'errors/ble_errors.dart';
import 'models/models.dart';

/// The BLE Peripheral (Server) role manager.
///
/// Use this class to advertise as a BLE peripheral, define a local GATT server,
/// and handle incoming connections from central devices.
///
/// ```dart
/// final peripheral = BlePeripheral();
///
/// // Define a GATT service
/// await peripheral.addService(GattServiceDefinition(
///   uuid: Guid('180D'),
///   characteristics: [
///     GattCharacteristicDefinition(
///       uuid: Guid('2A37'),
///       properties: CharacteristicProperties(notify: true, read: true),
///       permissions: CharacteristicPermissions(read: true),
///     ),
///   ],
/// ));
///
/// // Start advertising
/// await peripheral.startAdvertising(AdvertiseSettings(
///   localName: 'MyDevice',
///   serviceUuids: [Guid('180D')],
/// ));
///
/// // Handle incoming connections
/// peripheral.onCentralConnected.listen((device) {
///   print('Central connected: ${device.id}');
/// });
/// ```
class BlePeripheral {
  final BleLogger _logger;

  BlePlusPlatform get _platform => BlePlusPlatform.instance;

  /// Creates a new [BlePeripheral] instance.
  BlePeripheral({BleLogger? logger}) : _logger = logger ?? BleLogger();

  // ─── Advertising ─────────────────────────────────────────

  bool _isAdvertising = false;

  /// Whether currently advertising.
  bool get isAdvertising => _isAdvertising;

  /// Stream of advertising state changes.
  Stream<bool> get isAdvertisingStream => _platform.isAdvertisingStream;

  /// Start advertising as a BLE peripheral.
  ///
  /// Throws [BleUnsupportedError] if the platform doesn't support peripheral mode.
  Future<void> startAdvertising(AdvertiseSettings settings) async {
    if (!_platform.capabilities.peripheralRole) {
      throw const BleUnsupportedError(
        'Peripheral/Server role is not supported on this platform',
      );
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

  /// Stop advertising.
  Future<void> stopAdvertising() async {
    _logger.info('BlePeripheral', 'stopAdvertising()');
    await _platform.stopAdvertising();
    _isAdvertising = false;
  }

  // ─── GATT Server ─────────────────────────────────────────

  /// Add a service to the local GATT database.
  ///
  /// Can be called before or during advertising.
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

  /// Remove a service from the local GATT database.
  Future<void> removeService(Guid serviceUuid) async {
    await _platform.removeService(serviceUuid.str);
  }

  /// Remove all services from the local GATT database.
  Future<void> removeAllServices() async {
    await _platform.removeAllServices();
  }

  // ─── Incoming Events ─────────────────────────────────────

  /// Stream of central devices that connect to our GATT server.
  Stream<BleDevice> get onCentralConnected =>
      _platform.peripheralConnectionStream
          .where((event) => event.connected)
          .map((event) => BleDevice(id: event.deviceId));

  /// Stream of central devices that disconnect from our GATT server.
  Stream<BleDevice> get onCentralDisconnected =>
      _platform.peripheralConnectionStream
          .where((event) => !event.connected)
          .map((event) => BleDevice(id: event.deviceId));

  /// Stream of read requests from connected centrals.
  ///
  /// You MUST respond to each request using [ReadRequest.respond] or
  /// [ReadRequest.respondWithError].
  Stream<ReadRequest> get onReadRequest => _platform.readRequestStream.map(
        (event) => ReadRequest(
          requestId: event.requestId,
          central: BleDevice(id: event.deviceId),
          serviceUuid: Guid(event.serviceUuid),
          characteristicUuid: Guid(event.characteristicUuid),
          offset: event.offset,
        ),
      );

  /// Stream of write requests from connected centrals.
  ///
  /// If [WriteRequest.responseNeeded] is true, you MUST respond using
  /// [WriteRequest.respond] or [WriteRequest.respondWithError].
  Stream<WriteRequest> get onWriteRequest => _platform.writeRequestStream.map(
        (event) => WriteRequest(
          requestId: event.requestId,
          central: BleDevice(id: event.deviceId),
          serviceUuid: Guid(event.serviceUuid),
          characteristicUuid: Guid(event.characteristicUuid),
          value: event.value,
          offset: event.offset,
          responseNeeded: event.responseNeeded,
        ),
      );

  /// Stream of subscription changes (central subscribes/unsubscribes to notifications).
  Stream<SubscriptionChange> get onSubscriptionChange =>
      _platform.subscriptionChangeStream.map(
        (event) => SubscriptionChange(
          central: BleDevice(id: event.deviceId),
          serviceUuid: Guid(event.serviceUuid),
          characteristicUuid: Guid(event.characteristicUuid),
          isSubscribed: event.isSubscribed,
        ),
      );

  // ─── Sending Data ────────────────────────────────────────

  /// Send a notification or indication to subscribed centrals.
  ///
  /// [toDevice] - Send only to this specific central. If null, sends to all
  /// subscribed centrals.
  Future<void> notifyCharacteristic(
    Guid serviceUuid,
    Guid characteristicUuid,
    List<int> value, {
    BleDevice? toDevice,
  }) async {
    _logger.debug(
      'BlePeripheral',
      'notify($characteristicUuid, ${value.length} bytes)',
    );

    await _platform.sendNotification(
      serviceUuid.str,
      characteristicUuid.str,
      value,
      toDevice?.id,
    );
  }

  // ─── L2CAP Server ────────────────────────────────────────

  /// Publish an L2CAP channel for incoming connections.
  ///
  /// Returns the PSM (Protocol/Service Multiplexer) value that centrals
  /// should use to connect to this channel.
  ///
  /// Throws [BleUnsupportedError] on platforms that don't support L2CAP.
  Future<int> publishL2CapChannel({bool secure = true}) async {
    if (!_platform.capabilities.l2cap) {
      throw const BleUnsupportedError(
        'L2CAP channels are not supported on this platform',
      );
    }

    _logger.info('BlePeripheral', 'publishL2CapChannel(secure: $secure)');
    return _platform.publishL2CapChannel(secure);
  }

  /// Stream of incoming L2CAP channel connections from centrals.
  Stream<BleL2CapChannel> get onL2CapChannelOpened =>
      _platform.l2capServerChannelStream.map(
        (event) => BleL2CapChannel(
          channelId: event.channelId,
          psm: event.psm,
          device: BleDevice(id: event.deviceId),
        ),
      );

  /// Unpublish the L2CAP channel (stop accepting connections).
  Future<void> unpublishL2CapChannel() async {
    await _platform.unpublishL2CapChannel();
  }

  // ─── Cleanup ─────────────────────────────────────────────

  /// Dispose of all resources. Stops advertising and removes all services.
  Future<void> dispose() async {
    if (_isAdvertising) {
      await stopAdvertising();
    }
    await removeAllServices();
  }
}

