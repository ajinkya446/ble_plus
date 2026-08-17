import 'dart:async';

import 'package:flutter/services.dart';

import 'platform/ble_plus_platform.dart';
import 'platform/types/types.dart';
import 'platform/events/events.dart';
import 'ble_connection.dart';
import 'ble_logger.dart';
import 'errors/ble_errors.dart';
import 'errors/error_mapper.dart';
import 'models/models.dart';

/// The BLE Central role manager.
class BleCentral {
  final BleLogger _logger;
  BlePlusPlatform get _platform => BlePlusPlatform.instance;
  StreamSubscription<BleLogEntry>? _nativeLogSub;

  BleCentral({BleLogger? logger}) : _logger = logger ?? BleLogger() {
    // Relay the native plugin's diagnostic logs (Windows) to the user's logger
    // so scan/connect/discover/GATT steps can be watched live. On platforms
    // that emit no native logs the stream is Stream.empty() and this is a no-op.
    _nativeLogSub = _platform.nativeLogStream.listen((entry) {
      _logger.log(entry.level, 'native/${entry.tag}', entry.message);
    });
  }

  // ─── Adapter State ───────────────────────────────────────
  Stream<BleAdapterState> get adapterState => _platform.adapterStateStream;
  Future<bool> requestEnable() => _platform.requestEnable();
  PlatformCapabilities get capabilities => _platform.capabilities;

  // ─── Scanning ────────────────────────────────────────────
  bool _isScanning = false;
  StreamSubscription<BleScanResultData>? _scanSubscription;
  StreamController<BleScanResult>? _scanController;

  bool get isScanning => _isScanning;
  Stream<bool> get isScanningStream => _platform.isScanningStream;

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
    _scanController = controller;
    _isScanning = true;

    final platformStream = _platform.startScan(settings);
    _scanSubscription = platformStream.listen(
      (data) => controller.add(BleScanResult.fromData(data)),
      onError: (error) {
        _logger.error('BleCentral', 'Scan error: $error');
        controller.addError(BleScanError('Scan failed: $error'));
      },
      onDone: () {
        _isScanning = false;
        controller.close();
        _scanController = null;
      },
    );

    if (timeout != null) {
      Future.delayed(timeout, () {
        if (_isScanning) stopScan();
      });
    }

    return controller.stream;
  }

  Future<void> stopScan() async {
    _logger.debug('BleCentral', 'stopScan()');
    _isScanning = false;
    await _scanSubscription?.cancel();
    _scanSubscription = null;
    await _platform.stopScan();
    // Close the controller so listeners get onDone immediately
    await _scanController?.close();
    _scanController = null;
  }

  // ─── Connection ──────────────────────────────────────────
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
        .where((e) =>
            e.state == BleConnectionState.connected ||
            e.state == BleConnectionState.disconnected)
        .timeout(timeout, onTimeout: (sink) {
          sink.addError(BleTimeoutError('Connection timed out after $timeout'));
        })
        .first;

    try {
      await _platform.connect(device.id, settings);
    } on PlatformException catch (e) {
      throw mapPlatformException(e);
    }

    final event = await eventFuture;

    if (event.state == BleConnectionState.disconnected) {
      throw BleConnectionError(
        'Connection failed: ${event.errorMessage ?? "unknown"}',
        device: device,
        platformCode: event.errorCode,
      );
    }

    return BleConnection(device: device, logger: _logger);
  }

  Future<List<BleDevice>> get connectedDevices async {
    final ids = await _platform.getConnectedDevices();
    return ids.map((id) => BleDevice(id: id)).toList();
  }

  // ─── Background ──────────────────────────────────────────
  Future<void> enableBackground({
    String? androidNotificationTitle,
    String? androidNotificationBody,
    String? iosRestorationIdentifier,
  }) async {
    if (!capabilities.backgroundCentral) {
      _logger.warning('BleCentral', 'Background mode not supported on this platform');
      return;
    }
    await _platform.enableBackground(BackgroundSettings(
      iosRestorationIdentifier: iosRestorationIdentifier ?? 'ble_plus_central',
      androidNotificationTitle: androidNotificationTitle ?? 'BLE Active',
      androidNotificationBody: androidNotificationBody ?? 'Bluetooth running in background',
    ));
  }

  Future<void> disableBackground() => _platform.disableBackground();

  Stream<List<BleDevice>> get restoredDevices =>
      _platform.restoredDeviceIdsStream.map((ids) => ids.map((id) => BleDevice(id: id)).toList());

  Future<void> dispose() async {
    await _nativeLogSub?.cancel();
    _nativeLogSub = null;
    await stopScan();
    await _platform.dispose();
  }
}

enum ScanMode { lowPower, balanced, lowLatency, opportunistic }

