import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mttl_hub/models.dart';

// hub 2.15.38: the "live" SSE event and the per-strip cloud messages (samples in the hub's own format)
void main() {
  final full = jsonDecode('{"mac":"AAAAAA000001","name":"MTTL A000001","label":"Desk","model":"W01","fw":"F1.0.82","ip":"192.168.1.20",'
      '"online":true,"on":true,"power_w":12.50,"energy_kwh":1.234,"voltage":230.4,"current_a":0.05,"rssi":-60,"up_s":5,"mlock":false,'
      '"notify":31,"sched":false,"rule":false,"outlets":['
      '{"n":1,"on":true,"power_w":12.50,"energy_kwh":1.234,"temp_c":35,"label":"TV","locked":true,"protected":false,"keep_on":false,'
      '"amp_limit":0,"auto_off_min":0,"auto_off_in_s":-1,"sched":true,"rule":false},'
      '{"n":2,"on":false,"power_w":0.00,"energy_kwh":0.000,"temp_c":0,"label":"","locked":false,"protected":true,"keep_on":false,'
      '"amp_limit":2.5,"auto_off_min":30,"auto_off_in_s":90,"sched":false,"rule":false},'
      '{"n":3,"on":false,"power_w":0.00,"energy_kwh":0.000,"temp_c":0,"label":"","locked":false,"protected":false,"keep_on":false,'
      '"amp_limit":0,"auto_off_min":0,"auto_off_in_s":-1,"sched":false,"rule":false},'
      '{"n":4,"on":false,"power_w":0.00,"energy_kwh":0.000,"temp_c":0,"label":"","locked":false,"protected":false,"keep_on":false,'
      '"amp_limit":0,"auto_off_min":0,"auto_off_in_s":-1,"sched":false,"rule":false}]}') as Map<String, dynamic>;

  test('live numbers merge into the strip and keep everything else', () {
    final s = Strip.fromJson(full);
    final live = jsonDecode('{"ts":1760000000,"d":[{"mac":"AAAAAA000001","v":null,"r":-71,"up":65,'
        '"o":[[0,0.00,1.240,33,-1],[1,99.75,0.010,41,60],[0,0.00,0.000,0,-1],[1,5.00,0.002,30,-1]]}]}') as Map<String, dynamic>;
    final m = s.withLive((live['d'] as List).first as Map<String, dynamic>);
    expect(m.voltage, isNull);
    expect(m.rssi, -71);
    expect(m.upS, 65);
    expect(m.label, 'Desk');
    expect(m.fw, 'F1.0.82');
    expect(m.outlets[0].on, false);
    expect(m.outlets[0].energyKwh, 1.24);
    expect(m.outlets[0].label, 'TV');
    expect(m.outlets[0].locked, true);
    expect(m.outlets[0].hasSchedule, true);
    expect(m.outlets[1].on, true);
    expect(m.outlets[1].powerW, 99.75);
    expect(m.outlets[1].tempC, 41);
    expect(m.outlets[1].autoOffInS, 60);
    expect(m.outlets[1].autoOffMin, 30);
    expect(m.outlets[1].ampLimit, 2.5);
    expect(m.outlets[1].protected, true);
    expect(m.livePower, 104.75);
  });

  test('a short or broken live entry leaves the outlets as they were', () {
    final s = Strip.fromJson(full);
    final m = s.withLive({'mac': 'AAAAAA000001', 'v': 231.0, 'r': -50, 'up': 7, 'o': [[1, 2.0]]});
    expect(m.outlets[0].powerW, 12.5);
    expect(m.voltage, 231.0);
    final n = s.withLive({'mac': 'AAAAAA000001'});
    expect(n.outlets.length, 4);
    expect(n.upS, 5);
  });
}
