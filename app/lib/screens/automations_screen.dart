import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';

String _actText(int a) => a == 3 ? t('act_both') : (a == 2 ? t('act_off') : t('act_notify'));

class AutomationsScreen extends StatefulWidget {
  final AppState state;
  const AutomationsScreen({super.key, required this.state});

  @override
  State<AutomationsScreen> createState() => _AutomationsScreenState();
}

class _AutomationsScreenState extends State<AutomationsScreen> {
  AppState get s => widget.state;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (s.hubV2) await s.loadAutomations();
    if (mounted) setState(() => _loading = false);
  }

  void _edit([Automation? a]) {
    if (s.allStrips.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => AutomationEditor(state: s, initial: a)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final grouped = <String, List<Automation>>{};
        for (final a in s.automations) {
          grouped.putIfAbsent(a.mac, () => []).add(a);
        }
        final macs = <String>[];
        for (final st in s.allStrips) {
          if (grouped.containsKey(st.mac)) macs.add(st.mac);
        }
        for (final mac in grouped.keys) {
          if (!macs.contains(mac)) macs.add(mac);
        }

        return Scaffold(
          backgroundColor: C.bg,
          appBar: AppBar(
            backgroundColor: C.bg,
            surfaceTintColor: Colors.transparent,
            title: Text(t('auto_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          floatingActionButton: s.hubV2 && s.allStrips.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: () => _edit(),
                  backgroundColor: C.accent,
                  foregroundColor: C.onAccent,
                  icon: const Icon(Icons.add),
                  label: Text(t('auto_new'), style: const TextStyle(fontWeight: FontWeight.w700)),
                )
              : null,
          body: SafeArea(
            child: RefreshIndicator(
              color: C.accent,
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 96), children: [
                if (!s.hubV2) emptyCard(t('err_old_fw')) else ...[
                  _tempCard(),
                  if (s.hubHasStripProt) ...[const SizedBox(height: 14), _stripProtCard()],
                  const SizedBox(height: 14),
                  if (_loading) Center(child: CircularProgressIndicator(color: C.accent)),
                  if (!_loading && s.automations.isEmpty) emptyCard(t('auto_empty'), icon: Icons.bolt),
                  for (final mac in macs) ...[
                    _stripGroup(mac, grouped[mac]!),
                    const SizedBox(height: 14),
                  ],
                ],
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _stripGroup(String mac, List<Automation> rules) {
    final strip = s.live(mac);
    final stripName = strip != null ? s.stripName(strip) : mac;
    return Container(
      decoration: cardBox(radius: 20),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    stripName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(10)),
                  child: Text('${rules.length}', style: mono(12, color: C.muted)),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: C.border),
          for (var i = 0; i < rules.length; i++) ...[
            if (i > 0) Divider(height: 1, color: C.border.withValues(alpha: 0.5), indent: 70),
            _ruleRow(rules[i]),
          ],
        ],
      ),
    );
  }

  Widget _stripProtCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: cardBox(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.bolt, color: C.warn),
            const SizedBox(width: 10),
            Expanded(child: Text(t('vprot'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            Switch(value: s.vProtect, activeTrackColor: C.accent, onChanged: (v) => s.setStripProtection(vOn: v)),
          ]),
          Text(
            Tr.isAr
                ? 'فصل المشترك إذا هبط الفولت عن ${s.vMin} V أو تجاوز ${s.vMax} V'
                : 'Trip strip if voltage drops below ${s.vMin} V or exceeds ${s.vMax} V',
            style: TextStyle(color: C.muted, fontSize: 12, height: 1.5),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Text(Tr.isAr ? 'أدنى فولت' : 'Min voltage', style: TextStyle(color: C.textSoft, fontSize: 13)),
            Expanded(
              child: Slider(
                value: s.vMin.toDouble().clamp(180, 220),
                min: 180,
                max: 220,
                activeColor: C.accent,
                label: '${s.vMin} V',
                onChanged: s.vProtect ? (v) => setState(() => s.vMin = v.round()) : null,
                onChangeEnd: (v) => s.setStripProtection(vMinLimit: v.round()),
              ),
            ),
            Text('${s.vMin} V', textDirection: TextDirection.ltr, style: mono(14)),
          ]),
          Row(children: [
            Text(t('vprot_max'), style: TextStyle(color: C.textSoft, fontSize: 13)),
            Expanded(
              child: Slider(
                value: s.vMax.toDouble().clamp(225, 270),
                min: 225,
                max: 270,
                activeColor: C.accent,
                label: '${s.vMax} V',
                onChanged: s.vProtect ? (v) => setState(() => s.vMax = v.round()) : null,
                onChangeEnd: (v) => s.setStripProtection(vLimit: v.round()),
              ),
            ),
            Text('${s.vMax} V', textDirection: TextDirection.ltr, style: mono(14)),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: s.vRestore,
            activeTrackColor: C.accent,
            title: Text(t('vprot_restore'), style: const TextStyle(fontSize: 13)),
            onChanged: s.vProtect ? (v) => s.setStripProtection(vBack: v) : null,
          ),
          Divider(height: 22, color: C.border),
          Row(children: [
            Icon(Icons.electric_meter_outlined, color: C.danger),
            const SizedBox(width: 10),
            Expanded(child: Text(t('aprot'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            Switch(value: s.aProtect, activeTrackColor: C.accent, onChanged: (v) => s.setStripProtection(aOn: v)),
          ]),
          Text(t('aprot_sub', {'x': s.aMax.toStringAsFixed(1)}), style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
          Row(children: [
            Text(t('aprot_max'), style: TextStyle(color: C.textSoft, fontSize: 13)),
            Expanded(
              child: Slider(
                value: s.aMax.clamp(1, 16),
                min: 1,
                max: 16,
                activeColor: C.accent,
                label: '${s.aMax.toStringAsFixed(1)} A',
                onChanged: s.aProtect ? (v) => setState(() => s.aMax = (v * 2).round() / 2) : null,
                onChangeEnd: (v) => s.setStripProtection(aLimit: (v * 2).round() / 2),
              ),
            ),
            Text('${s.aMax.toStringAsFixed(1)} A', textDirection: TextDirection.ltr, style: mono(14)),
          ]),
        ]),
      );

  Widget _tempCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: cardBox(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Icon(Icons.thermostat, color: C.danger),
            const SizedBox(width: 10),
            Expanded(child: Text(t('temp_prot'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
            Switch(value: s.tempProtect, activeTrackColor: C.accent, onChanged: (v) => s.setTempProtection(enabled: v)),
          ]),
          Text(t('temp_prot_sub', {'x': s.tempMax}), style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
          Row(children: [
            Text(t('temp_max'), style: TextStyle(color: C.textSoft, fontSize: 13)),
            Expanded(
              child: Slider(
                value: s.tempMax.toDouble().clamp(40, 90),
                min: 40,
                max: 90,
                activeColor: C.accent,
                label: '${s.tempMax}°C',
                onChanged: s.tempProtect ? (v) => setState(() => s.tempMax = v.round()) : null,
                onChangeEnd: (v) => s.setTempProtection(max: v.round()),
              ),
            ),
            Text('${s.tempMax}°C', textDirection: TextDirection.ltr, style: mono(14)),
          ]),
        ]),
      );

  Widget _ruleRow(Automation a) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _edit(a),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(14)),
                child: Icon(
                    a.isBoth
                        ? Icons.shield_moon_outlined
                        : (a.isTemp
                            ? Icons.thermostat
                            : (a.isCurrent
                                ? Icons.electric_meter_outlined
                                : (a.above ? Icons.trending_up : Icons.trending_down))),
                    color: a.metric > 0 ? C.warn : C.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.label.isNotEmpty ? a.label : s.nameForMac(a.mac, a.outlet),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    _condText(a),
                    style: TextStyle(fontSize: 12, color: C.textSoft),
                  ),
                  Text('${s.nameForMac(a.mac, a.outlet)} ${Tr.isAr ? '←' : '→'} ${_actText(a.act)}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
                ]),
              ),
              Switch(
                value: a.enabled,
                activeTrackColor: C.accent,
                onChanged: (v) {
                  a.enabled = v;
                  s.saveAutomation(a);
                },
              ),
            ]),
          ),
        ),
      );
}

class AutomationEditor extends StatefulWidget {
  final AppState state;
  final Automation? initial;
  final String? presetMac;
  final int? presetOutlet;
  final String? presetRoom;
  const AutomationEditor({super.key, required this.state, this.initial, this.presetMac, this.presetOutlet, this.presetRoom});

  @override
  State<AutomationEditor> createState() => _AutomationEditorState();
}

class _AutomationEditorState extends State<AutomationEditor> {
  AppState get s => widget.state;
  late Automation a;
  late final TextEditingController _label, _watts, _limit2;
  bool _saving = false;
  String? _roomId;

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
    for (final mac in _roomId != null ? _roomMacs : [a.mac]) {
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
    final key = _roomId != null ? 'room:$_roomId|0' : '${a.mac}|${a.outlet}';
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
              },
              onChanged: (v) => setState(() {
                a.metric = v;
                if (v == 2) {
                  a.above = true;
                }
                _watts.text = v == 3 ? '10' : (v == 1 ? '60' : '1500');
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
                        : (a.isTemp ? t('threshold_temp') : t('threshold')),
                    suffixText: a.isCurrent ? 'A' : (a.isTemp ? '°C' : 'W'),
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
String _condText(Automation a) {
  if (!Tr.isAr) {
    final w = a.watts.toStringAsFixed(a.isCurrent ? 1 : 0);
    final cond = a.isBoth
        ? '${t('when_either')} $w W ${t('or')} ${a.limit2.toStringAsFixed(0)}°C'
        : a.isCurrent
            ? 'When current exceeds $w A'
            : '${a.isTemp ? t('when_temp') : t('when_power')} ${a.above ? t('rises_above') : t('drops_below')} $w ${a.isTemp ? '°C' : 'W'}';
    return '$cond for ${fmtDuration(a.holdS)}';
  }
  final w = a.watts.toStringAsFixed(a.isCurrent ? 1 : 0);
  final cond = a.isBoth
      ? 'لما الاستهلاك يعدّي $w وات أو الحرارة تعدّي ${a.limit2.toStringAsFixed(0)} درجة'
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
