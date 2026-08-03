import 'package:flutter_test/flutter_test.dart';
import 'package:ble_plus/ble_plus.dart';

void main() {
  test('BlePlusPlatform default instance is NoOp', () {
    // The default platform throws UnimplementedError on all methods
    final platform = BlePlusPlatform.instance;
    expect(platform, isNotNull);
    expect(platform.capabilities.centralRole, isFalse);
    expect(platform.capabilities.peripheralRole, isFalse);
  });
}
