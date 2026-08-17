import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:ble_plus/ble_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const BlePlusExampleApp());
}

class BlePlusExampleApp extends StatelessWidget {
  const BlePlusExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ble_plus Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// HOME PAGE — Tabs for Central, Peripheral, and Platform Info
// ═══════════════════════════════════════════════════════════════

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tabIndex,
        children: const [
          ScanPage(),
          PeripheralPage(),
          PlatformInfoPage(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (i) => setState(() => _tabIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bluetooth_searching), label: 'Scan'),
          NavigationDestination(icon: Icon(Icons.broadcast_on_personal), label: 'Advertise'),
          NavigationDestination(icon: Icon(Icons.info_outline), label: 'Platform'),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PLATFORM INFO PAGE — Shows capabilities & limitations
// ═══════════════════════════════════════════════════════════════

class PlatformInfoPage extends StatelessWidget {
  const PlatformInfoPage({super.key});

  @override
  Widget build(BuildContext context) {
    final central = BleCentral();
    final caps = central.capabilities;

    return Scaffold(
      appBar: AppBar(title: const Text('Platform Capabilities')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── Current platform ─────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current Platform',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  Text(_currentPlatformName(),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Capability flags ─────────────────────────────
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Supported Features',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _capRow('Central Role', caps.centralRole),
                  _capRow('Peripheral Role', caps.peripheralRole),
                  _capRow('L2CAP Channels', caps.l2cap),
                  _capRow('Background (Central)', caps.backgroundCentral),
                  _capRow('Background (Peripheral)', caps.backgroundPeripheral),
                  _capRow('Connection Parameters', caps.connectionParameters),
                  _capRow('Request MTU', caps.requestMtu),
                  _capRow('Bond Management', caps.bondManagement),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ─── Platform-specific notes ──────────────────────
          Card(
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      Text('Platform Limitations',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(_platformLimitations(),
                      style: const TextStyle(fontSize: 13, height: 1.5)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _capRow(String label, bool supported) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(
            supported ? Icons.check_circle : Icons.cancel,
            color: supported ? Colors.green : Colors.red,
            size: 20,
          ),
          const SizedBox(width: 12),
          Text(label),
        ],
      ),
    );
  }

  String _currentPlatformName() {
    if (kIsWeb) return 'Web (Chrome/Edge)';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isWindows) return 'Windows';
    return 'Unknown';
  }

  String _platformLimitations() {
    if (kIsWeb) {
      return '• Central role only — no peripheral/advertising\n'
          '• Scanning shows a device picker (not continuous)\n'
          '• Requires HTTPS and user gesture to scan\n'
          '• Chrome/Edge only (no Firefox/Safari)\n'
          '• No L2CAP, background, descriptors, or RSSI\n'
          '• Must specify service UUID filters when scanning';
    }
    if (Platform.isAndroid) {
      return '• L2CAP requires Android 10+ (API 29)\n'
          '• Peripheral requires BLUETOOTH_ADVERTISE permission\n'
          '• BLUETOOTH_SCAN + BLUETOOTH_CONNECT + LOCATION required\n'
          '• Background mode uses foreground service';
    }
    if (Platform.isIOS) {
      return '• MTU is auto-negotiated (cannot set manually)\n'
          '• Connection parameters are read-only\n'
          '• L2CAP requires iOS 11+\n'
          '• Background requires UIBackgroundModes in Info.plist';
    }
    if (Platform.isMacOS) {
      return '• MTU is auto-negotiated (cannot set manually)\n'
          '• Connection parameters are read-only\n'
          '• L2CAP requires macOS 10.14+\n'
          '• No background mode support\n'
          '• Requires Bluetooth entitlement';
    }
    if (Platform.isLinux) {
      return '• Central role only — no peripheral or L2CAP\n'
          '• Requires BlueZ package installed\n'
          '• No MTU request, RSSI, or descriptor R/W\n'
          '• No background support\n'
          '• Requires D-Bus permissions for scanning';
    }
    if (Platform.isWindows) {
      return '• Central role only — no peripheral or L2CAP\n'
          '• Requires Windows 10 or later\n'
          '• No RSSI read or descriptor R/W\n'
          '• No background support\n'
          '• MTU is auto-negotiated by OS';
    }
    return 'Unknown platform';
  }
}

// ═══════════════════════════════════════════════════════════════
// SCAN PAGE — Discovers nearby BLE devices
// ═══════════════════════════════════════════════════════════════

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  // ─── BLE Central instance with debug logging ─────────────
  // onLog only dumps to console (debugPrint). In debug mode the package logs
  // and the native plugin logs (channel "ble_plus/log") are visible; in release
  // everything is silenced (BleLogLevel.none) and the UI is never touched.
  late final _central = BleCentral(
    logger: BleLogger(
      level: kDebugMode ? BleLogLevel.debug : BleLogLevel.none,
      onLog: (level, tag, msg) => debugPrint('[$tag] $msg'),
    ),
  );

  final List<BleScanResult> _results = [];
  StreamSubscription<BleScanResult>? _scanSub;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    // Enable background mode on Windows: the runner will hide the window to
    // the tray on close and BLE keeps running (see BlePlusWindows).
    _central.enableBackground();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _central.dispose();
    super.dispose();
  }

  // ─── Request BLE permissions (Android 12+) ────────────────
  Future<bool> _requestPermissions() async {
    if (!kIsWeb && Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      final allGranted = statuses.values.every(
        (s) => s == PermissionStatus.granted,
      );

      if (!allGranted && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('BLE permissions are required to scan'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return allGranted;
    }
    return true; // iOS handles permissions via Info.plist prompts
  }

  // ─── Start scanning for BLE peripherals ──────────────────
  void _startScan() async {
    final granted = await _requestPermissions();
    if (!granted) return;

    setState(() {
      _results.clear();
      _scanning = true;
    });

    _scanSub = _central.startScan(
      // Optional: filter by specific service UUIDs
      // Note: Web REQUIRES service UUID filters
      // withServices: [Guid('180D')],
      timeout: const Duration(seconds: 15),
      allowDuplicates: false,
      scanMode: ScanMode.lowLatency,
    ).listen(
      (result) {
        setState(() {
          // Update existing or add new
          final idx = _results.indexWhere((r) => r.device.id == result.device.id);
          if (idx >= 0) {
            _results[idx] = result;
          } else {
            _results.add(result);
          }
          // Sort by signal strength
          _results.sort((a, b) => b.rssi.compareTo(a.rssi));
        });
      },
      onDone: () => setState(() => _scanning = false),
      onError: (e) {
        setState(() => _scanning = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scan error: $e'), backgroundColor: Colors.red),
        );
      },
    );
  }

  // ─── Stop scanning ───────────────────────────────────────
  Future<void> _stopScan() async {
    _scanSub?.cancel();
    _scanSub = null;
    setState(() => _scanning = false);
    await _central.stopScan();
  }

  // ─── Connect to device and navigate to detail page ───────
  Future<void> _connectToDevice(BleScanResult result) async {
    await _stopScan();

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DeviceDetailPage(central: _central, device: result.device),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Scanner'),
        actions: [
          if (_scanning)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
        ],
      ),
      body: _results.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _scanning ? 'Scanning for devices...' : 'Tap the button to scan',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (kIsWeb) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Web: A device picker will appear.\nYou must specify service UUIDs.',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            )
          : ListView.builder(
              itemCount: _results.length,
              itemBuilder: (ctx, i) {
                final r = _results[i];
                return _ScanResultTile(
                  result: r,
                  onTap: () => _connectToDevice(r),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scanning ? _stopScan : _startScan,
        icon: Icon(_scanning ? Icons.stop : Icons.search),
        label: Text(_scanning ? 'Stop' : 'Scan'),
      ),
    );
  }
}

// ─── Scan result list tile widget ──────────────────────────
class _ScanResultTile extends StatelessWidget {
  final BleScanResult result;
  final VoidCallback onTap;

  const _ScanResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final device = result.device;
    final ad = result.advertisementData;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: _rssiIcon(result.rssi),
        title: Text(
          device.displayName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device.id, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            if (ad.serviceUuids.isNotEmpty)
              Text('Services: ${ad.serviceUuids.length}', style: const TextStyle(fontSize: 11)),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('${result.rssi} dBm', style: const TextStyle(fontSize: 12)),
            if (ad.connectable)
              const Icon(Icons.bluetooth_connected, size: 16, color: Colors.blue),
          ],
        ),
        onTap: ad.connectable ? onTap : null,
      ),
    );
  }

  Widget _rssiIcon(int rssi) {
    final color = rssi > -60
        ? Colors.green
        : rssi > -80
            ? Colors.orange
            : Colors.red;
    return Icon(Icons.signal_cellular_alt, color: color);
  }
}

// ═══════════════════════════════════════════════════════════════
// DEVICE DETAIL PAGE — Connect, discover services, read/write
// ═══════════════════════════════════════════════════════════════

class DeviceDetailPage extends StatefulWidget {
  final BleCentral central;
  final BleDevice device;

  const DeviceDetailPage({super.key, required this.central, required this.device});

  @override
  State<DeviceDetailPage> createState() => _DeviceDetailPageState();
}

class _DeviceDetailPageState extends State<DeviceDetailPage> {
  BleConnection? _connection;
  List<BleService> _services = [];
  bool _connecting = false;
  String? _error;
  final Map<String, List<int>> _lastValues = {};
  final Map<String, StreamSubscription> _notifySubs = {};
  // Notification throttling: high-frequency notifications (ECG) would call
  // setState per sample and freeze the UI. The last pending value is stored
  // and a periodic Timer (~10 Hz) refreshes the screen.
  final Map<String, List<int>> _notifyPending = {};
  final Map<String, Timer> _notifyTimers = {};
  int? _rssi;
  BleConnectionParameters? _connParams;
  BleConnectionState _connectionState = BleConnectionState.connecting;
  BleBondState _bondState = BleBondState.none;
  StreamSubscription<BleConnectionState>? _connStateSub;
  StreamSubscription<BleBondState>? _bondStateSub;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _connStateSub?.cancel();
    _bondStateSub?.cancel();
    for (final t in _notifyTimers.values) {
      t.cancel();
    }
    _notifyTimers.clear();
    for (final sub in _notifySubs.values) {
      sub.cancel();
    }
    _connection?.disconnect();
    super.dispose();
  }

  // ─── Connect to the device ───────────────────────────────
  Future<void> _connect() async {
    setState(() {
      _connecting = true;
      _error = null;
    });

    try {
      // 1. Establish connection
      final connection = await widget.central.connect(
        widget.device,
        timeout: const Duration(seconds: 10),
        autoConnect: false,
      );

      // 2. Discover all services and characteristics
      final services = await connection.discoverServices();

      // 3. Request larger MTU (Android only; iOS/macOS/Windows auto-negotiate)
      await connection.requestMtu(512);

      setState(() {
        _connection = connection;
        _services = services;
        _connecting = false;
        _connectionState = BleConnectionState.connected;
      });

      // 4. Listen for connection state changes
      _connStateSub = connection.stateStream.listen((state) {
        setState(() => _connectionState = state);
        if (state == BleConnectionState.disconnected && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Device disconnected'), backgroundColor: Colors.orange),
          );
        }
      });

      // 5. Fetch and listen for bond state
      connection.bondState.then((state) {
        if (mounted) setState(() => _bondState = state);
      });
      _bondStateSub = connection.bondStateStream.listen((state) {
        setState(() => _bondState = state);
        if (mounted) {
          if (state == BleBondState.bonded) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Device paired/connected successfully'),
                backgroundColor: Colors.green,
              ),
            );
          } else if (state == BleBondState.none) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Device unpaired'),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      });
    } on BleTimeoutError catch (e) {
      setState(() {
        _error = 'Connection timed out: ${e.message}';
        _connecting = false;
      });
    } on BleConnectionError catch (e) {
      setState(() {
        _error = 'Connection failed: ${e.message}'
            '${e.platformMessage != null ? '\n[${e.platformMessage}]' : ''}'
            '${e.platformCode != null ? '\n(hr: 0x${e.platformCode!.toRadixString(16).toUpperCase()})' : ''}';
        _connecting = false;
      });
    } on BleError catch (e) {
      setState(() {
        _error = 'BLE Error: ${e.message}'
            '${e.platformMessage != null ? '\n[${e.platformMessage}]' : ''}';
        _connecting = false;
      });
    }
  }

  // ─── Read a characteristic value ─────────────────────────
  Future<void> _readCharacteristic(BleCharacteristic char) async {
    try {
      final value = await _connection!.readCharacteristic(char);
      setState(() => _lastValues[char.uuid.str] = value);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Read: $value')),
        );
      }
    } on BleError catch (e) {
      _showError('Read failed: ${_describeError(e)}');
    }
  }

  // ─── Write to a characteristic ───────────────────────────
  Future<void> _writeCharacteristic(BleCharacteristic char) async {
    final value = [0x01];
    try {
      await _connection!.writeCharacteristic(char, value, withResponse: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Wrote: $value')),
        );
      }
    } on BleError catch (e) {
      _showError('Write failed: ${_describeError(e)}');
    }
  }

  // ─── Subscribe to notifications ──────────────────────────
  void _toggleNotify(BleCharacteristic char) {
    final key = char.uuid.str;
    if (_notifySubs.containsKey(key)) {
      _notifySubs[key]!.cancel();
      _notifySubs.remove(key);
      _notifyTimers[key]?.cancel();
      _notifyTimers.remove(key);
      _notifyPending.remove(key);
      _connection!.unsubscribeFromCharacteristic(char);
      setState(() {});
    } else {
      // Notifications land in _notifyPending and a Timer (~10 Hz) refreshes
      // the UI with the latest value, instead of a setState per sample.
      _notifyTimers[key] ??= Timer.periodic(
        const Duration(milliseconds: 100),
        (_) {
          final pending = _notifyPending[key];
          if (pending != null && mounted) {
            setState(() => _lastValues[key] = pending);
          }
        },
      );
      final sub = _connection!.subscribeToCharacteristic(char).listen(
        (value) => _notifyPending[key] = value,
        onError: (e) {
          _showError('Notify error: $e');
          // The subscribe failed (e.g. Service Changed 2A05 on Windows):
          // revert the toggle so it is not left marked as active.
          _notifySubs[key]?.cancel();
          _notifySubs.remove(key);
          _notifyTimers[key]?.cancel();
          _notifyTimers.remove(key);
          _notifyPending.remove(key);
          if (mounted) setState(() {});
        },
      );
      _notifySubs[key] = sub;
      setState(() {});
    }
  }

  // ─── Read RSSI (not available on Web/Linux/Windows) ──────
  Future<void> _readRssi() async {
    try {
      final rssi = await _connection!.readRssi();
      setState(() => _rssi = rssi);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('RSSI: $rssi dBm')),
        );
      }
    } on BleUnsupportedError {
      _showError('RSSI read not supported on this platform');
    } on BleError catch (e) {
      _showError('RSSI read failed: ${_describeError(e)}');
    }
  }

  // ─── Toggle bond/pair state ───────────────────────────
  Future<void> _toggleBond() async {
    try {
      if (_bondState == BleBondState.bonded) {
        await _connection!.removeBond();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bond removed')),
          );
        }
      } else {
        await _connection!.createBond();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Pairing initiated...')),
          );
        }
      }
    } on BleError catch (e) {
      _showError('Bond failed: ${_describeError(e)}');
    }
  }

  // ─── Request connection parameters (Android only) ────────
  Future<void> _requestHighPriority() async {
    try {
      final params = await _connection!.requestConnectionParameters(
        ConnectionPriority.high,
      );
      setState(() => _connParams = params);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection priority set to high${params != null ? ' (interval: ${params.connectionIntervalMs}ms)' : ''}')),
        );
      }
    } on BleUnsupportedError {
      _showError('Connection parameters not supported on this platform');
    } on BleError catch (e) {
      _showError('Failed: ${_describeError(e)}');
    }
  }

  // ─── Disconnect ──────────────────────────────────────────
  Future<void> _disconnect() async {
    _connStateSub?.cancel();
    _bondStateSub?.cancel();
    for (final t in _notifyTimers.values) {
      t.cancel();
    }
    _notifyTimers.clear();
    _notifyPending.clear();
    for (final sub in _notifySubs.values) {
      sub.cancel();
    }
    _notifySubs.clear();
    await _connection?.disconnect();
    if (mounted) Navigator.pop(context);
  }

  // Formats a BleError including the structured detail sent by the native
  // plugin (platformMessage: stage, HRESULT, gattStatus, protocolError...).
  String _describeError(BleError e) => e.platformMessage != null
      ? '${e.message} [${e.platformMessage}]'
      : e.message;

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.device.displayName),
        actions: [
          if (_connection != null) ...[
            // ─── Bond/Pair button ──────────────────────────
            IconButton(
              icon: Icon(
                _bondState == BleBondState.bonded ? Icons.link : Icons.link_off,
                color: _bondState == BleBondState.bonded ? Colors.green : null,
              ),
              tooltip: _bondState == BleBondState.bonded ? 'Bonded (tap to unpair)' : 'Pair',
              onPressed: _toggleBond,
            ),
            // ─── RSSI button ───────────────────────────────
            IconButton(
              icon: const Icon(Icons.signal_cellular_alt),
              tooltip: 'Read RSSI',
              onPressed: _readRssi,
            ),
            // ─── Connection priority button ─────────────────
            IconButton(
              icon: const Icon(Icons.speed),
              tooltip: 'High Priority',
              onPressed: _requestHighPriority,
            ),
            // ─── Disconnect button ─────────────────────────
            IconButton(
              icon: const Icon(Icons.bluetooth_disabled),
              onPressed: _disconnect,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_connecting) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Connecting...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: _connect, child: const Text('Retry')),
          ],
        ),
      );
    }

    if (_services.isEmpty) {
      return const Center(child: Text('No services found'));
    }

    return ListView(
      children: [
        // ─── Connection info header ────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          color: _connectionState == BleConnectionState.connected
              ? Colors.indigo.shade50
              : Colors.red.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _connectionState == BleConnectionState.connected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
                    color: _connectionState == BleConnectionState.connected
                        ? Colors.indigo
                        : Colors.red,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.device.displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Text('MTU: ${_connection!.mtu} | Services: ${_services.length}',
                            style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // ─── State chips ────────────────────────────
              Wrap(
                spacing: 8,
                children: [
                  _StateChip(
                    label: _connectionState == BleConnectionState.connected
                        ? 'Connected'
                        : _connectionState == BleConnectionState.connecting
                            ? 'Connecting...'
                            : 'Disconnected',
                    color: _connectionState == BleConnectionState.connected
                        ? Colors.green
                        : _connectionState == BleConnectionState.connecting
                            ? Colors.orange
                            : Colors.red,
                    icon: Icons.bluetooth,
                  ),
                  _StateChip(
                    label: _bondState == BleBondState.bonded
                        ? 'Paired'
                        : _bondState == BleBondState.bonding
                            ? 'Pairing...'
                            : 'Not Paired',
                    color: _bondState == BleBondState.bonded
                        ? Colors.blue
                        : _bondState == BleBondState.bonding
                            ? Colors.orange
                            : Colors.grey,
                    icon: _bondState == BleBondState.bonded
                        ? Icons.lock
                        : Icons.lock_open,
                  ),
                ],
              ),
              if (_rssi != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('RSSI: $_rssi dBm',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
              if (_connParams != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Conn Interval: ${_connParams!.connectionIntervalMs}ms',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ),
            ],
          ),
        ),

        // ─── Services and characteristics list ─────────────
        ..._services.expand((service) => [
          _ServiceHeader(service: service),
          ...service.characteristics.map((char) => _CharacteristicTile(
            characteristic: char,
            lastValue: _lastValues[char.uuid.str],
            isNotifying: _notifySubs.containsKey(char.uuid.str),
            onRead: char.properties.read ? () => _readCharacteristic(char) : null,
            onWrite: (char.properties.write || char.properties.writeWithoutResponse)
                ? () => _writeCharacteristic(char)
                : null,
            onNotify: (char.properties.notify || char.properties.indicate)
                ? () => _toggleNotify(char)
                : null,
          )),
        ]),
      ],
    );
  }
}

// ─── Service header widget ─────────────────────────────────
class _ServiceHeader extends StatelessWidget {
  final BleService service;
  const _ServiceHeader({required this.service});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.grey.shade200,
      child: Text(
        'Service: ${service.uuid}',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ─── Characteristic tile widget ────────────────────────────
class _CharacteristicTile extends StatelessWidget {
  final BleCharacteristic characteristic;
  final List<int>? lastValue;
  final bool isNotifying;
  final VoidCallback? onRead;
  final VoidCallback? onWrite;
  final VoidCallback? onNotify;

  const _CharacteristicTile({
    required this.characteristic,
    this.lastValue,
    this.isNotifying = false,
    this.onRead,
    this.onWrite,
    this.onNotify,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // UUID
              Text(
                characteristic.uuid.str,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              const SizedBox(height: 4),

              // Properties
              Text(
                'Properties: ${characteristic.properties}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),

              // Last value
              if (lastValue != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Value: $lastValue',
                    style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                  ),
                ),
              ],

              // Action buttons
              const SizedBox(height: 8),
              Row(
                children: [
                  if (onRead != null)
                    _ActionChip(label: 'Read', icon: Icons.download, onTap: onRead!),
                  if (onWrite != null)
                    _ActionChip(label: 'Write', icon: Icons.upload, onTap: onWrite!),
                  if (onNotify != null)
                    _ActionChip(
                      label: isNotifying ? 'Unsubscribe' : 'Notify',
                      icon: isNotifying ? Icons.notifications_off : Icons.notifications,
                      onTap: onNotify!,
                      active: isNotifying,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  const _ActionChip({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 11)),
        onPressed: onTap,
        backgroundColor: active ? Colors.indigo.shade100 : null,
      ),
    );
  }
}

// ─── State indicator chip ──────────────────────────────────
class _StateChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StateChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 14, color: color),
      label: Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
      backgroundColor: color.withValues(alpha: 0.1),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: EdgeInsets.zero,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// PERIPHERAL PAGE — Advertise as a BLE device
// ═══════════════════════════════════════════════════════════════

class PeripheralPage extends StatefulWidget {
  const PeripheralPage({super.key});

  @override
  State<PeripheralPage> createState() => _PeripheralPageState();
}

class _PeripheralPageState extends State<PeripheralPage> {
  final _peripheral = BlePeripheral(
    logger: BleLogger(
      level: BleLogLevel.debug,
      onLog: (level, tag, msg) => debugPrint('[$tag] $msg'),
    ),
  );

  bool _advertising = false;
  bool _serviceAdded = false;
  final List<String> _log = [];

  @override
  void initState() {
    super.initState();
    // Only subscribe to the peripheral streams on platforms that support them;
    // on central-only platforms (Web/Linux/Windows) the channel does not exist.
    if (_peripheralSupported) {
      _setupListeners();
    }
  }

  void _setupListeners() {
    _peripheral.onCentralConnected.listen((device) {
      _addLog('✅ Central connected: ${device.id}');
    });

    _peripheral.onCentralDisconnected.listen((device) {
      _addLog('❌ Central disconnected: ${device.id}');
    });

    _peripheral.onReadRequest.listen((request) {
      _addLog('📖 Read request for ${request.characteristicUuid}');
      request.respond([0x00, 72]); // flags=0, HR=72
    });

    _peripheral.onWriteRequest.listen((request) {
      _addLog('✏️ Write: ${request.value} from ${request.central.id}');
      if (request.responseNeeded) request.respond();
    });

    _peripheral.onSubscriptionChange.listen((change) {
      final action = change.isSubscribed ? 'subscribed' : 'unsubscribed';
      _addLog('🔔 $action: ${change.characteristicUuid}');
    });
  }

  Future<void> _addHeartRateService() async {
    await _peripheral.addService(GattServiceDefinition(
      uuid: Guid('180D'), // Heart Rate Service
      characteristics: [
        GattCharacteristicDefinition(
          uuid: Guid('2A37'), // Heart Rate Measurement
          properties: const CharacteristicProperties(notify: true, read: true),
          permissions: const CharacteristicPermissions(read: true),
        ),
        GattCharacteristicDefinition(
          uuid: Guid('2A38'), // Body Sensor Location
          properties: const CharacteristicProperties(read: true),
          permissions: const CharacteristicPermissions(read: true),
          initialValue: [1], // 1 = Chest
        ),
      ],
    ));
    _serviceAdded = true;
    _addLog('📋 Heart Rate Service added');
  }

  Future<void> _toggleAdvertising() async {
    try {
      if (_advertising) {
        await _peripheral.stopAdvertising();
        setState(() => _advertising = false);
        _addLog('⏹ Advertising stopped');
      } else {
        if (!_serviceAdded) await _addHeartRateService();

        await _peripheral.startAdvertising(AdvertiseSettings(
          localName: 'ble_plus_demo',
          serviceUuids: [Guid('180D')],
          connectable: true,
        ));
        setState(() => _advertising = true);
        _addLog('▶️ Advertising as "ble_plus_demo"');
      }
    } on BleUnsupportedError catch (e) {
      _addLog('⚠️ ${e.message}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Peripheral not supported: ${e.message}'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } on BleError catch (e) {
      _addLog('❗ Error: ${e.message}');
    }
  }

  Future<void> _sendHeartRate() async {
    final hr = 60 + (DateTime.now().second % 40);
    try {
      await _peripheral.notifyCharacteristic(
        Guid('180D'),
        Guid('2A37'),
        [0x00, hr],
      );
      _addLog('💓 Sent HR: $hr bpm');
    } on BleError catch (e) {
      _addLog('❗ Notify error: ${e.message}');
    }
  }

  void _addLog(String msg) {
    setState(() {
      _log.insert(0, '[${TimeOfDay.now().format(context)}] $msg');
      if (_log.length > 100) _log.removeLast();
    });
  }

  @override
  void dispose() {
    _peripheral.dispose();
    super.dispose();
  }

  bool get _peripheralSupported {
    // Check platform capabilities
    if (kIsWeb) return false;
    if (Platform.isLinux || Platform.isWindows) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BLE Peripheral'),
        actions: [
          if (_advertising)
            IconButton(
              icon: const Icon(Icons.favorite),
              tooltip: 'Send Heart Rate',
              onPressed: _sendHeartRate,
            ),
        ],
      ),
      body: !_peripheralSupported
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block, size: 64, color: Colors.grey.shade400),
                    const SizedBox(height: 16),
                    Text(
                      'Peripheral Role Not Supported',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Peripheral mode (advertising + GATT server) is available on Android, iOS, and macOS only.\n\n'
                      'Web, Linux, and Windows support Central role only.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
            )
          : Column(
              children: [
                // ─── Control section ──────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  color: _advertising ? Colors.green.shade50 : Colors.grey.shade50,
                  child: Row(
                    children: [
                      Icon(
                        _advertising ? Icons.broadcast_on_personal : Icons.broadcast_on_personal_outlined,
                        color: _advertising ? Colors.green : Colors.grey,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _advertising ? 'Advertising as "ble_plus_demo"' : 'Not advertising',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _advertising ? Colors.green.shade800 : Colors.grey.shade600,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: _toggleAdvertising,
                        child: Text(_advertising ? 'Stop' : 'Start'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),

                // ─── Event log ───────────────────────────────
                Expanded(
                  child: _log.isEmpty
                      ? const Center(child: Text('Events will appear here'))
                      : ListView.builder(
                          itemCount: _log.length,
                          padding: const EdgeInsets.all(8),
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(_log[i], style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}
