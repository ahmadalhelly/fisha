import 'package:flutter_test/flutter_test.dart';
import 'package:mttl_hub/services/automation_text.dart';

void main() {
  test('reads the hub automation message', () {
    final m = AutomationMsg.parse('Fan guard · 692 W > 500 W · o:2,4')!;
    expect(m.label, 'Fan guard');
    expect(m.metric, 'W');
    expect(m.cuts, [2, 4]);
    expect(m.sentence((n) => 'Outlet $n', ar: false), 'Rule "Fan guard": Power 692 W is above the limit 500 W — switched off: Outlet 2, Outlet 4');
    final v = AutomationMsg.parse('231 V > 190 V')!;
    expect(v.sentence((n) => 'x', ar: true), 'الجهد 231 فولت أعلى من الحد 190 فولت');
    expect(AutomationMsg.parse('178 V < 190 V')!.sentence((n) => 'x', ar: true), 'الجهد 178 فولت أقل من الحد 190 فولت');
    final d = AutomationMsg.parse('Room 2 · heater · 692.3 W > 500 W · o:3')!;
    expect(d.label, 'Room 2 · heater');
    expect(d.reading, '692.3');
    expect(d.cuts, [3]);
    expect(AutomationMsg.parse('72 C > 70 C')!.sentence((n) => 'x', ar: false), 'Temperature 72 °C is above the limit 70 °C');
    expect(AutomationMsg.parse('something else'), isNull);
  });
}
