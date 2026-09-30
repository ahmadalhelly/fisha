import 'package:flutter_test/flutter_test.dart';
import 'package:mttl_hub/models.dart';

void main() {
  test('parses a hub state payload', () {
    final s = Strip.fromJson({
      'mac': '88D0391778E8',
      'fw': '0.1.54-1.0.105',
      'online': true,
      'power_w': 12.5,
      'energy_kwh': 1.2,
      'voltage': 232.2,
      'rssi': -31,
      'outlets': [
        {'n': 1, 'on': true, 'power_w': 12.5, 'energy_kwh': 1.2, 'temp_c': 26},
        {'n': 2, 'on': false, 'power_w': 0, 'energy_kwh': 0, 'temp_c': 28},
      ],
    });
    expect(s.outlets.length, 2);
    expect(s.onCount, 1);
    expect(s.maxTemp, 28);
    expect(s.withOutlets(0, false).onCount, 0);
  });
}
