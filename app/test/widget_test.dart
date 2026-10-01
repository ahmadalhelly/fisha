import 'package:flutter_test/flutter_test.dart';
import 'package:mttl_hub/models.dart';

void main() {
  test('parses a hub state strip', () {
    final s = Strip.fromJson({
      'mac': '88d0391778e8',
      'fw': '0.1.54',
      'online': true,
      'voltage': 233.1,
      'rssi': -60,
      'label': 'Desk',
      'outlets': [
        {'n': 2, 'on': true, 'power_w': 11.0, 'temp_c': 27, 'protected': true, 'auto_off_min': 30, 'auto_off_in_s': 120},
        {'n': 1, 'on': false, 'power_w': 0, 'temp_c': 25, 'locked': true},
      ],
    });
    expect(s.mac, '88D0391778E8');
    expect(s.outlets.first.n, 1);
    expect(s.outlets.first.locked, true);
    expect(s.livePower, 11.0);
    expect(s.anyProtectedOn, true);
    expect(s.outlets.last.autoOffInS, 120);
    expect(s.withOutlets(0, false).onCount, 0);
  });

  test('parses energy history', () {
    final e = EnergyData.fromJson({
      'mac': 'AA',
      'time_ok': true,
      'today': 20261001,
      'today_wh': [10, 0, 5, 0],
      'days': [
        {'date': 20260930, 'wh': [100, 0, 0, 1]},
      ],
    });
    expect(e.days.single.total, 101);
    expect(e.todayWh[2], 5);
  });
}
