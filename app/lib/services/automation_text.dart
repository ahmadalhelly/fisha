import '../i18n.dart';

/// What the hub puts in an "automation" event: "[rule name · ]231 V > 190 V[ · o:1,3]" (the reading, the limit it was
/// compared with, and the outlets it switched off). Written as one clear sentence in the language of the app, with the
/// units spelled out in words so Arabic keeps its direction.
class AutomationMsg {
  final String label;
  final String metric; // W, A, C or V
  final String reading;
  final bool above;
  final String limit;
  final List<int> cuts;
  const AutomationMsg(this.label, this.metric, this.reading, this.above, this.limit, this.cuts);

  static final _re = RegExp(r'^(?:(.*) · )?(-?[\d.]+) ([WACV]) ([<>]) (-?[\d.]+) [WACV](?: · o:([\d,]+))?$');

  static AutomationMsg? parse(String msg) {
    final m = _re.firstMatch(msg.trim());
    if (m == null) return null;
    return AutomationMsg(
      (m.group(1) ?? '').trim(),
      m.group(3)!,
      m.group(2)!,
      m.group(4) == '>',
      m.group(5)!,
      [for (final x in (m.group(6) ?? '').split(',')) if (int.tryParse(x) != null) int.parse(x)],
    );
  }

  String _what(bool ar) => switch (metric) {
        'W' => ar ? 'القدرة' : 'power',
        'A' => ar ? 'التيار' : 'current',
        'C' => ar ? 'الحرارة' : 'temperature',
        _ => ar ? 'الجهد' : 'voltage',
      };

  String _unit(bool ar) => switch (metric) {
        'W' => ar ? 'وات' : 'W',
        'A' => ar ? 'أمبير' : 'A',
        'C' => ar ? 'درجة' : '°C',
        _ => ar ? 'فولت' : 'V',
      };

  /// "الجهد 231 فولت أعلى من الحد 190 فولت" / "voltage 231 V is above the limit 190 V"
  String reading_(bool ar) => ar
      ? '${_what(true)} $reading ${_unit(true)} ${above ? 'أعلى' : 'أقل'} من الحد $limit ${_unit(true)}'
      : '${_what(false)} $reading ${_unit(false)} is ${above ? 'above' : 'below'} the limit $limit ${_unit(false)}';

  /// the whole sentence: the rule, what was read, and what was switched off
  String sentence(String Function(int) outletName, {bool? ar}) {
    final a = ar ?? Tr.isAr;
    final base = reading_(a);
    final off = cuts.isEmpty ? '' : (a ? ' — اتقفل: ' : ' — switched off: ') + cuts.map(outletName).join(a ? '، ' : ', ');
    final rule = label.isEmpty ? '' : (a ? 'القاعدة «$label»: ' : 'Rule "$label": ');
    return '$rule$base$off';
  }

  String title({bool? ar}) {
    final a = ar ?? Tr.isAr;
    return label.isEmpty ? (a ? 'أتمتة اشتغلت' : 'Automation fired') : (a ? 'أتمتة: $label' : 'Automation: $label');
  }
}
