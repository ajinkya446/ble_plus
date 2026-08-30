import 'dart:async';

import 'package:ble_plus_platform_interface/ble_plus_platform_interface.dart';

import 'models/models.dart';

/// An L2CAP Connection-Oriented Channel for high-throughput data transfer.
///
/// L2CAP channels provide a socket-like interface for streaming data
/// between BLE devices without the overhead of GATT operations.
///
/// Supported on: iOS 11+, Android 10+ (API 29+), macOS 10.14+.
class BleL2CapChannel {
  final int _channelId;
  final int _psm;
  final BleDevice _device;
  bool _isOpen = true;

  BlePlusPlatform get _platform => BlePlusPlatform.instance;

  /// Creates an L2CAP channel handle.
  BleL2CapChannel({
    required int channelId,
    required int psm,
    required BleDevice device,
  })  : _channelId = channelId,
        _psm = psm,
        _device = device;

  /// The PSM this channel operates on.
  int get psm => _psm;

  /// The remote device.
  BleDevice get device => _device;

  /// Whether the channel is currently open.
  bool get isOpen => _isOpen;

  /// Stream of incoming data on this channel.
  Stream<List<int>> get inputStream => _platform.l2capDataStream
      .where((event) => event.channelId == _channelId)
      .map((event) => event.data);

  /// Write data to the channel.
  ///
  /// Throws if the channel is closed.
  Future<void> write(List<int> data) async {
    if (!_isOpen) {
      throw StateError('L2CAP channel is closed');
    }
    await _platform.writeL2Cap(_channelId, data);
  }

  /// Close the channel.
  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;
    await _platform.closeL2CapChannel(_channelId);
  }

  /// Stream that emits when this channel is closed (by either side).
  Stream<void> get onClose => _platform.l2capCloseStream
      .where((event) => event.channelId == _channelId)
      .map((event) {
    _isOpen = false;
  });
}

