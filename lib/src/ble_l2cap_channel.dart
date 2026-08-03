import 'platform/ble_plus_platform.dart';
import 'models/ble_device.dart';

/// An L2CAP Connection-Oriented Channel.
class BleL2CapChannel {
  final int _channelId;
  final int _psm;
  final BleDevice _device;
  bool _isOpen = true;

  BlePlusPlatform get _platform => BlePlusPlatform.instance;

  BleL2CapChannel({required int channelId, required int psm, required BleDevice device})
      : _channelId = channelId,
        _psm = psm,
        _device = device;

  int get psm => _psm;
  BleDevice get device => _device;
  bool get isOpen => _isOpen;

  Stream<List<int>> get inputStream => _platform.l2capDataStream
      .where((e) => e.channelId == _channelId)
      .map((e) => e.data);

  Future<void> write(List<int> data) async {
    if (!_isOpen) throw StateError('L2CAP channel is closed');
    await _platform.writeL2Cap(_channelId, data);
  }

  Future<void> close() async {
    if (!_isOpen) return;
    _isOpen = false;
    await _platform.closeL2CapChannel(_channelId);
  }

  Stream<void> get onClose => _platform.l2capCloseStream
      .where((e) => e.channelId == _channelId)
      .map((e) { _isOpen = false; });
}

