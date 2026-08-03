import 'package:flutter_test/flutter_test.dart';
import 'package:ble_plus/ble_plus.dart';

void main() {
  group('BleCentral', () {
    test('can be instantiated', () {
      final central = BleCentral();
      expect(central, isNotNull);
      expect(central.isScanning, isFalse);
    });

    test('capabilities returns PlatformCapabilities', () {
      final central = BleCentral();
      final caps = central.capabilities;
      expect(caps, isA<PlatformCapabilities>());
    });
  });

  group('BlePeripheral', () {
    test('can be instantiated', () {
      final peripheral = BlePeripheral();
      expect(peripheral, isNotNull);
      expect(peripheral.isAdvertising, isFalse);
    });
  });

  group('Guid', () {
    test('normalizes 16-bit UUID', () {
      final guid = Guid('180D');
      expect(guid.str, '0000180d-0000-1000-8000-00805f9b34fb');
    });

    test('normalizes 32-bit UUID', () {
      final guid = Guid('0000180D');
      expect(guid.str, '0000180d-0000-1000-8000-00805f9b34fb');
    });

    test('equality works', () {
      expect(Guid('180D'), equals(Guid('0000180d-0000-1000-8000-00805f9b34fb')));
    });

    test('hashCode consistent with equality', () {
      expect(Guid('180D').hashCode, equals(Guid('0000180d-0000-1000-8000-00805f9b34fb').hashCode));
    });
  });

  group('BleDevice', () {
    test('equality by id', () {
      final a = BleDevice(id: 'AA:BB:CC:DD:EE:FF', name: 'A');
      final b = BleDevice(id: 'AA:BB:CC:DD:EE:FF', name: 'B');
      expect(a, equals(b));
    });

    test('displayName falls back to id', () {
      final device = BleDevice(id: 'AA:BB:CC:DD:EE:FF');
      expect(device.displayName, 'AA:BB:CC:DD:EE:FF');
    });

    test('displayName prefers name', () {
      final device = BleDevice(id: 'AA:BB:CC:DD:EE:FF', name: 'MyDevice');
      expect(device.displayName, 'MyDevice');
    });
  });

  group('CharacteristicProperties', () {
    test('fromBitmask and toBitmask roundtrip', () {
      const props = CharacteristicProperties(read: true, notify: true);
      final mask = props.toBitmask();
      final restored = CharacteristicProperties.fromBitmask(mask);
      expect(restored.read, isTrue);
      expect(restored.notify, isTrue);
      expect(restored.write, isFalse);
      expect(restored.indicate, isFalse);
    });
  });

  group('BleErrors', () {
    test('BleUnsupportedError is a BleError', () {
      const error = BleUnsupportedError('Not supported');
      expect(error, isA<BleError>());
      expect(error.message, 'Not supported');
    });

    test('BleConnectionError includes device info', () {
      const device = BleDevice(id: 'AA:BB:CC:DD:EE:FF');
      const error = BleConnectionError('Failed', device: device, platformCode: 133);
      expect(error.device, equals(device));
      expect(error.platformCode, 133);
      expect(error.toString(), contains('133'));
    });

    test('BleTimeoutError is a BleError', () {
      const error = BleTimeoutError('Timed out');
      expect(error, isA<BleError>());
    });
  });

  group('BleLogger', () {
    test('logs at correct level', () {
      final logs = <String>[];
      final logger = BleLogger(
        level: BleLogLevel.info,
        onLog: (level, tag, message) => logs.add('[$tag] $message'),
      );

      logger.debug('test', 'debug msg'); // Below level, should not log
      logger.info('test', 'info msg');   // At level, should log
      logger.error('test', 'error msg'); // Above level, should log

      expect(logs, hasLength(2));
      expect(logs[0], '[test] info msg');
      expect(logs[1], '[test] error msg');
    });
  });
}
