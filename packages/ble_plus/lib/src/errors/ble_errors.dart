import '../models/ble_device.dart';

/// Base class for all BLE errors.
///
/// Uses a sealed class hierarchy so that users can exhaustively match
/// on error types in switch statements.
sealed class BleError implements Exception {
  /// Human-readable error message.
  final String message;

  /// Platform-specific error code (if available).
  final int? platformCode;

  /// Platform-specific error message (if available).
  final String? platformMessage;

  const BleError(this.message, {this.platformCode, this.platformMessage});

  @override
  String toString() => '$runtimeType: $message'
      '${platformCode != null ? ' (code: $platformCode)' : ''}'
      '${platformMessage != null ? ' [$platformMessage]' : ''}';
}

/// The requested feature is not supported on this platform.
class BleUnsupportedError extends BleError {
  const BleUnsupportedError(super.message);
}

/// Bluetooth adapter is not available, turned off, or unauthorized.
class BleAdapterError extends BleError {
  const BleAdapterError(super.message, {super.platformCode});
}

/// Connection to a device failed or was unexpectedly lost.
class BleConnectionError extends BleError {
  /// The device that the connection failed for (if available).
  final BleDevice? device;

  const BleConnectionError(
    super.message, {
    this.device,
    super.platformCode,
    super.platformMessage,
  });
}

/// A GATT operation (read/write/notify/discover) failed.
class BleGattError extends BleError {
  /// The unified GATT error code.
  final GattErrorCode code;

  const BleGattError(
    super.message, {
    required this.code,
    super.platformCode,
  });
}

/// A scan operation failed.
class BleScanError extends BleError {
  const BleScanError(super.message, {super.platformCode});
}

/// A required Bluetooth permission was not granted.
class BlePermissionError extends BleError {
  /// The permissions that are missing.
  final List<String> missingPermissions;

  const BlePermissionError(
    super.message, {
    required this.missingPermissions,
  });
}

/// An operation timed out.
class BleTimeoutError extends BleError {
  const BleTimeoutError(super.message);
}

/// Unified GATT error codes across all platforms.
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

