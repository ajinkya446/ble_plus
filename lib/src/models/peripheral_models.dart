import '../platform/ble_plus_platform.dart';
import '../platform/types/types.dart';
import 'ble_device.dart';

/// Read request from a central (peripheral mode).
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

  Future<void> respond(List<int> value) =>
      BlePlusPlatform.instance.respondToReadRequest(requestId, value);

  Future<void> respondWithError(GattError error) =>
      BlePlusPlatform.instance.respondWithError(requestId, error.code);
}

/// Write request from a central (peripheral mode).
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

  Future<void> respond() =>
      BlePlusPlatform.instance.respondToWriteRequest(requestId);

  Future<void> respondWithError(GattError error) =>
      BlePlusPlatform.instance.respondWithError(requestId, error.code);
}

/// Subscription change event (peripheral mode).
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

/// Standard GATT error codes.
enum GattError {
  requestNotSupported(0x06),
  invalidOffset(0x07),
  insufficientAuthentication(0x05),
  insufficientEncryption(0x0F),
  invalidAttributeLength(0x0D),
  readNotPermitted(0x02),
  writeNotPermitted(0x03),
  failure(0x0E);

  final int code;
  const GattError(this.code);
}

