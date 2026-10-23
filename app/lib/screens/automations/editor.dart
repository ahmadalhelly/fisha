part of '../automations_screen.dart';

class AutomationEditor extends StatefulWidget {
  final AppState state;
  final Automation? initial;
  final String? presetMac;
  final int? presetOutlet;
  final String? presetRoom;
  final int? presetMetric; // 4 = a whole-strip voltage rule, from the strip card
  const AutomationEditor({super.key, required this.state, this.initial, this.presetMac, this.presetOutlet, this.presetRoom, this.presetMetric});

  @override
  State<AutomationEditor> createState() => _AutomationEditorState();
}

class _AutomationEditorState extends State<AutomationEditor> {
  AppState get s => widget.state;
  late Automation a;
  late final TextEditingController _label, _watts, _limit2;
  bool _saving = false;
  String? _roomId;
  // the rule is for every strip of the hub: 0 = the whole strip, 1..4 = that outlet on each strip
  int? _allOutlet;

  List<String> get _roomMacs {
    final r = s.rooms.where((x) => x.id == _roomId).firstOrNull;
    return r == null ? const [] : r.stripMacs.where((m) => s.allStrips.any((st) => st.mac == m)).toList();
  }

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    a = i != null
        ? Automation.fromJson(i.toJson())
        : Automation(
            mac: widget.presetMac ?? s.allStrips.first.mac,
            outlet: widget.presetOutlet ?? 1,
            above: false,
            watts: 5,
            holdS: 60,
            act: 1,
            metric: 0,
            limit2: 60,
          );
    if (i == null && widget.presetMetric == 4) {
      a.metric = 4;
      a.outlet = 0;
      a.above = false;
      a.watts = 190;
      a.act = 3;
    }
    if (i == null && widget.presetRoom != null) {
      _roomId = widget.presetRoom;
      if (_roomMacs.isNotEmpty) {
        a.mac = _roomMacs.first;
        a.outlet = 0;
      } else {
        _roomId = null;
      }
    }
    _label = TextEditingController(text: a.label);
    _watts = TextEditingController(text: a.watts.toStringAsFixed(0));
    _limit2 = TextEditingController(text: a.limit2.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _label.dispose();
    _watts.dispose();
    _limit2.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    a.label = _label.text.replaceAll('"', '').trim();
    a.watts = double.tryParse(_watts.text.trim()) ?? a.watts;
    a.limit2 = double.tryParse(_limit2.text.trim()) ?? a.limit2;
    if (a.isBoth) a.above = true;
    setState(() => _saving = true);
    var ok = true;
    final macs = _roomId != null ? _roomMacs : (_allOutlet != null ? [for (final st in s.allStrips) st.mac] : [a.mac]);
    for (final mac in macs) {
      final one = Automation.fromJson(a.toJson())..mac = mac;
      if (_roomId != null && one.label.isEmpty) one.label = s.rooms.firstWhere((r) => r.id == _roomId).name;
      ok = await s.saveAutomation(one) && ok;
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, t('delete'), t('auto_title'), ok: t('delete'), danger: true)) return;
    await s.deleteAutomation(a.aid);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final targets = <MapEntry<String, String>>[];
    for (final st in s.allStrips) {
      targets.add(MapEntry('${st.mac}|0', '${s.stripName(st)} · ${t('whole_strip')}'));
      for (final o in st.outlets) {
        targets.add(MapEntry('${st.mac}|${o.n}', '${s.stripName(st)} · ${s.outletName(st, o.n)}'));
      }
    }
    // a whole room is saved as one rule per strip in it
    if (widget.initial == null) {
      for (final r in s.rooms) {
        if (r.stripMacs.any((m) => s.allStrips.any((st) => st.mac == m))) {
          targets.insert(0, MapEntry('room:${r.id}|0', '${r.name} · ${t('whole_room')}'));
        }
      }
    }
    // the same rule on every strip of this hub (a new rule only): the whole strip, or one outlet number
    if (widget.initial == null && s.allStrips.length > 1) {
      for (var n = 4; n >= 1; n--) {
        targets.insert(0, MapEntry('all|$n', Tr.isAr ? 'كل المشتركات · مخرج $n' : 'All strips · outlet $n'));
      }
      targets.insert(0, MapEntry('all|0', Tr.isAr ? 'كل المشتركات · المشترك كله' : 'All strips · whole strip'));
    }
    final key = _roomId != null ? 'room:$_roomId|0' : (_allOutlet != null ? 'all|$_allOutlet' : '${a.mac}|${a.outlet}');
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.initial == null ? t('auto_new') : t('auto_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [if (widget.initial != null) IconButton(onPressed: _delete, icon: Icon(Icons.delete_outline, color: C.danger))],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
          section(t('sched_target'), [
            DropdownButtonFormField<String>(
              value: targets.any((e) => e.key == key) ? key : targets.first.key,
              isExpanded: true,
              dropdownColor: C.surface2,
              items: [for (final e in targets) DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))],
              onChanged: (v) {
                if (v == null) return;
                if (v.startsWith('all|')) {
                  setState(() {
                    _roomId = null;
                    _allOutlet = int.parse(v.substring(4));
                    a.outlet = _allOutlet!;
                    if (a.isVoltage) a.metric = 0;
                  });
                  return;
                }
                _allOutlet = null;
                if (v.startsWith('room:')) {
                  final id = v.substring(5).split('|').first;
                  final r = s.rooms.firstWhere((x) => x.id == id);
                  setState(() {
                    _roomId = id;
                    a.mac = r.stripMacs.firstWhere((m) => s.allStrips.any((st) => st.mac == m));
                    a.outlet = 0;
                  });
                  return;
                }
                _roomId = null;
                final p = v.split('|');
                setState(() {
                  a.mac = p[0];
                  a.outlet = int.parse(p[1]);
                  if (a.outlet != 0 && a.isVoltage) a.metric = 0;
                });
              },
            ),
          ]),
          const SizedBox(height: 14),
          section(t('rule_watch'), [
            Segmented<int>(
              value: a.metric,
              items: {
                0: t('metric_power_s'),
                1: t('metric_temp_s'),
                2: t('metric_both'),
                3: Tr.isAr ? 'التيار (A)' : 'Current (A)',
                // voltage is the whole strip's: only for a whole-strip rule
                if (a.outlet == 0 && _allOutlet == null) 4: Tr.isAr ? 'الجهد (V)' : 'Voltage (V)',
              },
              onChanged: (v) => setState(() {
                a.metric = v;
                if (v == 2) {
                  a.above = true;
                }
                _watts.text = v == 3 ? '10' : (v == 1 ? '60' : (v == 4 ? (a.above ? '250' : '190') : '1500'));
                _limit2.text = '60';
              }),
            ),
            if (a.outlet == 0)
              Text(
                  a.isBoth
                      ? t('rule_strip_both')
                      : (a.isTemp
                          ? t('rule_strip_temp')
                          : (a.isCurrent
                              ? (Tr.isAr ? 'حماية تيار المشترك بالكامل' : 'Whole-strip current protection')
                              : a.isVoltage
                                  ? (Tr.isAr ? 'الجهد بيتقاس للمشترك كله، والفصل بيقفل مخارجه غير المحمية.' : 'Voltage is measured for the whole strip; a cut switches off its unprotected outlets.')
                                  : t('rule_strip_power'))),
                  style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
            if (a.isBoth)
              Text(t('rule_both_hint'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.5))
            else
              Segmented<bool>(
                  value: a.above, items: {false: t('drops_below'), true: t('rises_above')}, onChanged: (v) => setState(() => a.above = v)),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _watts,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textDirection: TextDirection.ltr,
                  decoration: InputDecoration(
                    labelText: a.isCurrent
                        ? (Tr.isAr ? 'حد التيار (أمبير)' : 'Current limit (A)')
                        : a.isVoltage
                            ? (Tr.isAr ? 'حد الجهد (100-280 فولت)' : 'Voltage limit (100-280 V)')
                            : (a.isTemp ? t('threshold_temp') : t('threshold')),
                    suffixText: a.isCurrent ? 'A' : (a.isVoltage ? 'V' : (a.isTemp ? '°C' : 'W')),
                  ),
                ),
              ),
              if (a.isBoth) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _limit2,
                    keyboardType: TextInputType.number,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: t('threshold_temp'), suffixText: '°C'),
                  ),
                ),
              ],
            ]),
            Text(t('held_for'), style: TextStyle(color: C.muted, fontSize: 13)),
            DurationPicker(value: a.holdS, maxHours: 17, onChanged: (v) => setState(() => a.holdS = v < 5 ? 5 : v)),
          ]),
          const SizedBox(height: 14),
          if (a.outlet == 0) ...[emptyCard(t('rule_strip_protect'), icon: Icons.shield_outlined), const SizedBox(height: 14)],
          section(t('then'), [
            Segmented<int>(
              value: a.act,
              items: {1: t('act_notify'), 2: t('act_off'), 3: t('act_both')},
              onChanged: (v) => setState(() => a.act = v),
            ),
          ]),
          const SizedBox(height: 14),
          section(t('label_opt'), [
            TextField(controller: _label, maxLength: 30, decoration: InputDecoration(hintText: t('auto_label_hint'))),
            Text(t('auto_note'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
          ]),
          const SizedBox(height: 16),
          primaryButton(t('save'), _saving ? null : _save, icon: Icons.check),
        ]),
      ),
    );
  }
}

/// "لما القدرة تنزل تحت 3 وات لمدة 2 دقيقة": Arabic units and words, so the line reads in one direction
/// (mixing "3 W · 2 د" in RTL text scrambled the order).
String automationCondText(Automation a) {
  if (!Tr.isAr) {
    final w = a.watts.toStringAsFixed(a.isCurrent ? 1 : 0);
    final cond = a.isBoth
        ? '${t('when_either')} $w W ${t('or')} ${a.limit2.toStringAsFixed(0)}°C'
        : a.isVoltage
            ? 'When the voltage ${a.above ? t('rises_above') : t('drops_below')} $w V'
        : a.isCurrent
            ? 'When current exceeds $w A'
            : '${a.isTemp ? t('when_temp') : t('when_power')} ${a.above ? t('rises_above') : t('drops_below')} $w ${a.isTemp ? '°C' : 'W'}';
    return '$cond for ${fmtDuration(a.holdS)}';
  }
  final w = a.watts.toStringAsFixed(a.isCurrent ? 1 : 0);
  final cond = a.isBoth
      ? 'لما الاستهلاك يعدّي $w وات أو الحرارة تعدّي ${a.limit2.toStringAsFixed(0)} درجة'
      : a.isVoltage
          ? 'لما الجهد ${a.above ? 'يطلع فوق' : 'ينزل تحت'} $w فولت'
      : a.isCurrent
          ? 'لما التيار يعدّي $w أمبير'
          : a.isTemp
              ? 'لما الحرارة ${a.above ? 'تطلع فوق' : 'تنزل تحت'} $w درجة'
              : 'لما القدرة ${a.above ? 'تطلع فوق' : 'تنزل تحت'} $w وات';
  return '$cond لمدة ${_arDuration(a.holdS)}';
}

String _arCount(int n, String one, String two, String few, String many) =>
    n == 1 ? one : (n == 2 ? two : (n <= 10 ? '$n $few' : '$n $many'));

String _arDuration(int sec) {
  if (sec < 60) return _arCount(sec, 'ثانية', 'ثانيتين', 'ثواني', 'ثانية');
  final h = sec ~/ 3600, m = (sec % 3600) ~/ 60, s = sec % 60;
  final parts = <String>[
    if (h > 0) _arCount(h, 'ساعة', 'ساعتين', 'ساعات', 'ساعة'),
    if (m > 0) _arCount(m, 'دقيقة', 'دقيقتين', 'دقايق', 'دقيقة'),
    if (s > 0 && h == 0) _arCount(s, 'ثانية', 'ثانيتين', 'ثواني', 'ثانية'),
  ];
  return parts.join(' و');
}
