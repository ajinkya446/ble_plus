import '../models/ble_device.dart';

/// Base class for all BLE errors.
sealed class BleError implements Exception {
  final String message;
  final int? platformCode;
  final String? platformMessage;

  const BleError(this.message, {this.platformCode, this.platformMessage});

  @override
  String toString() => '$runtimeType: $message'
      '${platformCode != null ? ' (code: $platformCode)' : ''}'
      '${platformMessage != null ? ' [$platformMessage]' : ''}';
}

class BleUnsupportedError extends BleError {
  const BleUnsupportedError(super.message);
}

class BleAdapterError extends BleError {
  const BleAdapterError(super.message, {super.platformCode});
}

class BleConnectionError extends BleError {
  final BleDevice? device;
  const BleConnectionError(super.message, {this.device, super.platformCode, super.platformMessage});
}

class BleGattError extends BleError {
  final GattErrorCode code;
  const BleGattError(super.message,
      {required this.code, super.platformCode, super.platformMessage});
}

class BleScanError extends BleError {
  const BleScanError(super.message, {super.platformCode});
}

class BlePermissionError extends BleError {
  final List<String> missingPermissions;
  const BlePermissionError(super.message, {required this.missingPermissions});
}

class BleTimeoutError extends BleError {
  const BleTimeoutError(super.message);
}

enum GattErrorCode {
  success,
  invalidHandle,
  readNotPermitted,
  writeNotPermitted,
  invalidPdu,
  insufficientAuthentication,
  requestNotSupported,
  invalidOffset,
  insufficientEncryption,
  connectionCongested,
  failure,
  unknown,
}

