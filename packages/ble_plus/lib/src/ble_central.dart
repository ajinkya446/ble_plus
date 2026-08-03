import 'dart:async';

import 'package:ble_plus_platform_interface/ble_plus_platform_interface.dart';

import 'ble_connection.dart';
import 'ble_logger.dart';
import 'errors/ble_errors.dart';
import 'models/models.dart';

/// The BLE Central role manager.
///
/// Use this class to scan for peripherals, connect to devices, and perform
/// GATT operations (read, write, subscribe to notifications).
///
/// ```dart
/// final central = BleCentral();
///
/// // Listen to adapter state
/// central.adapterState.listen((state) => print('Adapter: $state'));
///
/// // Scan for devices
/// central.startScan(withServices: [Guid('180D')]).listen((result) {
///   print('Found: ${result.device.displayName} RSSI: ${result.rssi}');
/// });
///
/// // Connect
/// final connection = await central.connect(device);
/// final services = await connection.discoverServices();
/// ```
class BleCentral {
  final BleLogger _logger;

  BlePlusPlatform get _platform => BlePlusPlatform.instance;

  /// Creates a new [BleCentral] instance.
  BleCentral({BleLogger? logger}) : _logger = logger ?? BleLogger();

  // ─── Adapter State ───────────────────────────────────────

  /// Stream of Bluetooth adapter state changes.
  Stream<BleAdapterState> get adapterState => _platform.adapterStateStream;

  /// Request the user to enable Bluetooth.
  /// Returns true if Bluetooth was enabled, false otherwise.
  /// On iOS this is a no-op (the system handles the prompt).
  Future<bool> requestEnable() => _platform.requestEnable();

  /// The capabilities of the current platform implementation.
  PlatformCapabilities get capabilities => _platform.capabilities;

  // ─── Scanning ────────────────────────────────────────────

  bool _isScanning = false;
  StreamSubscription? _scanSubscription;

  /// Whether a scan is currently active.
  bool get isScanning => _isScanning;

  /// Stream that emits true/false when scanning starts/stops.
  Stream<bool> get isScanningStream => _platform.isScanningStream;

  /// Start scanning for BLE peripherals.
  ///
  /// Returns a broadcast stream of [BleScanResult] objects.
  /// The scan continues until [stopScan] is called or [timeout] expires.
  ///
  /// [withServices] - Filter results to devices advertising these service UUIDs.
  /// [timeout] - Automatically stop scanning after this duration.
  /// [allowDuplicates] - Report the same device multiple times.
  /// [scanMode] - Scan mode (affects power consumption and latency).
  Stream<BleScanResult> startScan({
    List<Guid>? withServices,
    Duration? timeout,
    bool allowDuplicates = false,
    ScanMode scanMode = ScanMode.lowLatency,
  }) {
    _logger.debug('BleCentral', 'startScan(services: $withServices, timeout: $timeout)');

    final settings = ScanSettings(
      withServices: withServices?.map((g) => g.str).toList(),
      scanMode: scanMode.index,
      allowDuplicates: allowDuplicates,
    );

    final controller = StreamController<BleScanResult>.broadcast();

    _isScanning = true;

    final platformStream = _platform.startScan(settings);
    _scanSubscription = platformStream.listen(
      (data) {
        controller.add(BleScanResult.fromData(data));
      },
      onError: (error) {
        _logger.error('BleCentral', 'Scan error: $error');
        controller.addError(
          BleScanError('Scan failed: $error'),
        );
      },
      onDone: () {
        _isScanning = false;
        controller.close();
      },
    );

    // Auto-stop after timeout
    if (timeout != null) {
      Future.delayed(timeout, () {
        if (_isScanning) {
          stopScan();
        }
      });
    }

    return controller.stream;
  }

  /// Stop the current scan.
  Future<void> stopScan() async {
    _logger.debug('BleCentral', 'stopScan()');
    _isScanning = false;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _platform.stopScan();
  }

  // ─── Connection ──────────────────────────────────────────

  /// Connect to a BLE device.
  ///
  /// Returns a [BleConnection] handle for interacting with the device.
  /// Throws [BleConnectionError] if connection fails.
  /// Throws [BleTimeoutError] if the connection times out.
  Future<BleConnection> connect(
    BleDevice device, {
    Duration timeout = const Duration(seconds: 15),
    bool autoConnect = false,
  }) async {
    _logger.info('BleCentral', 'connect(${device.id}, timeout: $timeout)');

    final settings = ConnectionSettings(
      timeoutMs: timeout.inMilliseconds,
      autoConnect: autoConnect,
    );

    // Start listening for connection events BEFORE calling connect
    // to avoid race condition where the event arrives before we subscribe.
    final eventFuture = _platform.connectionEventStream
        .where((e) => e.deviceId == device.id)
        .where(
          (e) =>
              e.state == BleConnectionState.connected ||
              e.state == BleConnectionState.disconnected,
        )
        .timeout(timeout, onTimeout: (sink) {
          sink.addError(BleTimeoutError(
            'Connection to ${device.displayName} timed out after $timeout',
          ));
        })
        .first;

    try {
      await _platform.connect(device.id, settings);
    } catch (e) {
      throw BleConnectionError(
        'Failed to connect to ${device.displayName}: $e',
        device: device,
      );
    }

    // Wait for the connected state event
    final event = await eventFuture;

    if (event.state == BleConnectionState.disconnected) {
      throw BleConnectionError(
        'Connection to ${device.displayName} failed: ${event.errorMessage ?? "unknown error"}',
        device: device,
        platformCode: event.errorCode,
      );
    }

    return BleConnection(device: device, logger: _logger);
  }

  /// Get all currently connected BLE devices.
  Future<List<BleDevice>> get connectedDevices async {
    final ids = await _platform.getConnectedDevices();
    return ids.map((id) => BleDevice(id: id)).toList();
  }

  // ─── Background ──────────────────────────────────────────

  /// Enable background BLE operations.
  ///
  /// On iOS: enables CoreBluetooth state restoration.
  /// On Android: starts a foreground service for long-running BLE work.
  /// On other platforms: no-op.
  Future<void> enableBackground({
    String? androidNotificationTitle,
    String? androidNotificationBody,
    String? iosRestorationIdentifier,
  }) async {
    if (!capabilities.backgroundCentral) {
      _logger.warning(
        'BleCentral',
        'Background mode not supported on this platform',
      );
      return;
    }

    await _platform.enableBackground(BackgroundSettings(
      iosRestorationIdentifier: iosRestorationIdentifier ?? 'ble_plus_central',
      androidNotificationTitle: androidNotificationTitle ?? 'BLE Active',
      androidNotificationBody: androidNotificationBody ?? 'Bluetooth is running in the background',
    ));
  }

  /// Disable background BLE operations.
  Future<void> disableBackground() => _platform.disableBackground();

  /// Stream of devices restored from a previous session (iOS only).
  Stream<List<BleDevice>> get restoredDevices =>
      _platform.restoredDeviceIdsStream.map(
        (ids) => ids.map((id) => BleDevice(id: id)).toList(),
      );

  // ─── Cleanup ─────────────────────────────────────────────

  /// Dispose of all resources held by this central manager.
  Future<void> dispose() async {
    await stopScan();
    await _platform.dispose();
  }
}

/// Scan mode (affects power consumption and discovery latency).
enum ScanMode {
  /// Low power scan (longer intervals, less battery usage).
  lowPower,

  /// Balanced scan mode.
  balanced,

  /// Low latency scan (fastest discovery, highest battery usage).
  lowLatency,

  /// Opportunistic scan (piggybacks on other apps' scans, Android only).
  opportunistic,
}

