import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'types/types.dart';
import 'events/events.dart';
import 'method_channel_ble_plus.dart';

/// The platform interface that native implementations must extend.
abstract class BlePlusPlatform extends PlatformInterface {
  BlePlusPlatform() : super(token: _token);
  static final Object _token = Object();

  static BlePlusPlatform _instance = MethodChannelBlePlus();
  static BlePlusPlatform get instance => _instance;
  static set instance(BlePlusPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  PlatformCapabilities get capabilities => const PlatformCapabilities();

  // ── Adapter ──────────────────────────────────────────────
  Stream<BleAdapterState> get adapterStateStream => const Stream.empty();
  Future<bool> requestEnable() async => false;

  // ── Central: Scanning ────────────────────────────────────
  Stream<BleScanResultData> startScan(ScanSettings settings) => const Stream.empty();
  Future<void> stopScan() async {}
  Stream<bool> get isScanningStream => const Stream.empty();

  // ── Central: Connection ──────────────────────────────────
  Future<void> connect(String deviceId, ConnectionSettings settings) async {}
  Future<void> disconnect(String deviceId) async {}
  Stream<BleConnectionEvent> get connectionEventStream => const Stream.empty();
  Future<List<String>> getConnectedDevices() async => [];

  // ── Central: Bond / Pair ─────────────────────────────────
  Future<void> createBond(String deviceId) async {}
  Future<void> removeBond(String deviceId) async {}
  Future<int> getBondState(String deviceId) async => 0; // BleBondState.none
  Stream<BondStateEvent> get bondStateStream => const Stream.empty();

  // ── Central: GATT ────────────────────────────────────────
  Future<List<BleServiceData>> discoverServices(String deviceId) async => [];
  Future<List<int>> readCharacteristic(String deviceId, String serviceUuid, String charUuid) async => [];
  Future<void> writeCharacteristic(String deviceId, String serviceUuid, String charUuid, List<int> value, bool withResponse) async {}
  Future<void> setNotification(String deviceId, String serviceUuid, String charUuid, bool enable) async {}
  Stream<CharacteristicValueEvent> get characteristicValueStream => const Stream.empty();
  Future<List<int>> readDescriptor(String deviceId, String serviceUuid, String charUuid, String descUuid) async => [];
  Future<void> writeDescriptor(String deviceId, String serviceUuid, String charUuid, String descUuid, List<int> value) async {}

  // ── Central: MTU / RSSI ──────────────────────────────────
  Future<int> requestMtu(String deviceId, int mtu) async => 23;
  Stream<MtuChangeEvent> get mtuChangeStream => const Stream.empty();
  Future<int> readRssi(String deviceId) async => 0;

  // ── Central: Connection Parameters ───────────────────────
  Future<BleConnectionParametersData?> getConnectionParameters(String deviceId) async => null;
  Future<BleConnectionParametersData?> requestConnectionPriority(String deviceId, int priority) async => null;

  // ── Central: L2CAP ───────────────────────────────────────
  Future<int> openL2CapChannel(String deviceId, int psm, bool secure) async => -1;
  Future<void> closeL2CapChannel(int channelId) async {}
  Future<void> writeL2Cap(int channelId, List<int> data) async {}
  Stream<L2CapDataEvent> get l2capDataStream => const Stream.empty();
  Stream<L2CapCloseEvent> get l2capCloseStream => const Stream.empty();

  // ── Peripheral: Advertising ──────────────────────────────
  Future<void> startAdvertising(AdvertiseSettingsData settings) async {}
  Future<void> stopAdvertising() async {}
  Stream<bool> get isAdvertisingStream => const Stream.empty();

  // ── Peripheral: GATT Server ──────────────────────────────
  Future<void> addService(GattServiceDefinitionData service) async {}
  Future<void> removeService(String uuid) async {}
  Future<void> removeAllServices() async {}
  Future<void> sendNotification(String serviceUuid, String charUuid, List<int> value, String? deviceId) async {}
  Future<void> respondToReadRequest(int requestId, List<int> value) async {}
  Future<void> respondToWriteRequest(int requestId) async {}
  Future<void> respondWithError(int requestId, int errorCode) async {}

  // ── Peripheral: Events ───────────────────────────────────
  Stream<PeripheralConnectionEvent> get peripheralConnectionStream => const Stream.empty();
  Stream<ReadRequestEvent> get readRequestStream => const Stream.empty();
  Stream<WriteRequestEvent> get writeRequestStream => const Stream.empty();
  Stream<SubscriptionChangeEvent> get subscriptionChangeStream => const Stream.empty();

  // ── Peripheral: L2CAP Server ─────────────────────────────
  Future<int> publishL2CapChannel(bool secure) async => -1;
  Future<void> unpublishL2CapChannel() async {}
  Stream<L2CapChannelOpenedEvent> get l2capServerChannelStream => const Stream.empty();

  // ── Background ───────────────────────────────────────────
  Future<void> enableBackground(BackgroundSettings settings) async {}
  Future<void> disableBackground() async {}
  Stream<List<String>> get restoredDeviceIdsStream => const Stream.empty();

  // ── Diagnostics: native logs ─────────────────────────────
  // Stream of log entries emitted by the native plugin (channel
  // "ble_plus/log"). Empty by default: only platforms that emit them
  // (Windows) override it. BleCentral relays them to its BleLogger.
  Stream<BleLogEntry> get nativeLogStream => const Stream.empty();

  Future<void> dispose() async {}
}

