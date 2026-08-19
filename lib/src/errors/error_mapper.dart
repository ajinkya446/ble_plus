import 'package:flutter/services.dart';

import 'ble_errors.dart';

/// Converts a platform error (e.g. a [PlatformException] thrown by a method
/// channel when replying with `result->Error`) into the matching [BleError]
/// subclass, honoring the public API contract of throwing [BleError].
BleError mapPlatformException(Object error) {
  if (error is BleError) {
    return error;
  }
  if (error is PlatformException) {
    final message = error.message ?? error.code;
    final parsed = _parseDetails(error.details);
    return switch (error.code) {
      'TIMEOUT' => BleTimeoutError(message),
      'NOT_CONNECTED' => BleConnectionError(message,
          platformCode: parsed.platformCode,
          platformMessage: parsed.platformMessage),
      'CONNECTION_FAILED' => BleConnectionError(message,
          platformCode: parsed.platformCode,
          platformMessage:
              parsed.platformMessage ?? error.details?.toString()),
      'UNSUPPORTED' => BleUnsupportedError(message),
      'NOT_FOUND' => BleGattError(message,
          code: GattErrorCode.invalidHandle,
          platformCode: parsed.platformCode,
          platformMessage: parsed.platformMessage),
      'GATT_ERROR' => BleGattError(message,
          code: GattErrorCode.failure,
          platformCode: parsed.platformCode,
          platformMessage: parsed.platformMessage),
      _ => BleGattError(message,
          code: GattErrorCode.unknown,
          platformCode: parsed.platformCode,
          platformMessage: parsed.platformMessage),
    };
  }
  return BleGattError('$error', code: GattErrorCode.unknown);
}

/// Extracts from `details` (the 3rd argument of `result->Error(...)` sent by
/// the native plugin, see `ErrorDetails`/`SendError` in windows/ble_plus_plugin.*)
/// the platform code (hex HRESULT → int) and a readable message with the stage,
/// deviceId and the GATT/protocolError statuses that accompanied the failure.
({int? platformCode, String? platformMessage}) _parseDetails(Object? details) {
  if (details is! Map) {
    return (platformCode: null, platformMessage: null);
  }
  final stage = details['stage'];
  final message = details['message'];
  final deviceId = details['deviceId'];
  final gattStatus = details['gattStatus'];
  final protocolError = details['protocolError'];

  final parts = <String>[
    if (stage is String && stage.isNotEmpty) stage,
    if (message is String && message.isNotEmpty) message,
    if (deviceId is String && deviceId.isNotEmpty) 'deviceId=$deviceId',
    if (gattStatus is int) 'gattStatus=$gattStatus',
    if (protocolError is int) 'protocolError=$protocolError',
  ];

  final hr = details['hresult'];
  return (
    platformCode: hr is String
        ? int.tryParse(hr.replaceFirst('0x', ''), radix: 16)
        : null,
    platformMessage: parts.isEmpty ? null : parts.join(' | '),
  );
}
