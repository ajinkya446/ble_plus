import 'package:ble_plus_platform_interface/ble_plus_platform_interface.dart';

import 'ble_device.dart';

/// A read request from a connected central device (peripheral mode).
class ReadRequest {
  final int requestId;
  final BleDevice central;
  final Guid serviceUuid;
  final Guid characteristicUuid;
  final int offset;

  const ReadRequest({
    required this.requestId,
    required this.central,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.offset,
  });

  /// Respond to this read request with data.
  Future<void> respond(List<int> value) {
    return BlePlusPlatform.instance.respondToReadRequest(requestId, value);
  }

  /// Respond to this read request with an error.
  Future<void> respondWithError(GattError error) {
    return BlePlusPlatform.instance.respondWithError(requestId, error.code);
  }
}

/// A write request from a connected central device (peripheral mode).
class WriteRequest {
  final int requestId;
  final BleDevice central;
  final Guid serviceUuid;
  final Guid characteristicUuid;
  final List<int> value;
  final int offset;
  final bool responseNeeded;

  const WriteRequest({
    required this.requestId,
    required this.central,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.value,
    required this.offset,
    required this.responseNeeded,
  });

  /// Respond to this write request (acknowledge success).
  Future<void> respond() {
    return BlePlusPlatform.instance.respondToWriteRequest(requestId);
  }

  /// Respond to this write request with an error.
  Future<void> respondWithError(GattError error) {
    return BlePlusPlatform.instance.respondWithError(requestId, error.code);
  }
}

/// Notification subscription change event (peripheral mode).
class SubscriptionChange {
  final BleDevice central;
  final Guid serviceUuid;
  final Guid characteristicUuid;
  final bool isSubscribed;

  const SubscriptionChange({
    required this.central,
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.isSubscribed,
  });
}

/// Standard GATT error codes for responding to requests.
enum GattError {
  /// Request not supported.
  requestNotSupported(0x06),

  /// Invalid offset.
  invalidOffset(0x07),

  /// Insufficient authentication.
  insufficientAuthentication(0x05),

  /// Insufficient encryption.
  insufficientEncryption(0x0F),

  /// Invalid attribute length.
  invalidAttributeLength(0x0D),

  /// Read not permitted.
  readNotPermitted(0x02),

  /// Write not permitted.
  writeNotPermitted(0x03),

  /// Generic failure.
  failure(0x0E);

  final int code;
  const GattError(this.code);
}

