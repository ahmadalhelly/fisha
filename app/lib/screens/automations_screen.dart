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
      builder: (context, _) => Scaffold(
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
                const SizedBox(height: 14),
                if (_loading) Center(child: CircularProgressIndicator(color: C.accent)),
                if (!_loading && s.automations.isEmpty) emptyCard(t('auto_empty'), icon: Icons.bolt),
                for (final a in s.automations) Padding(padding: const EdgeInsets.only(bottom: 10), child: _card(a)),
              ],
            ]),
          ),
        ),
      ),
    );
  }

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
                divisions: 50,
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

  Widget _card(Automation a) => Material(
        color: C.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: C.border)),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _edit(a),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(14)),
                child: Icon(a.above ? Icons.trending_up : Icons.trending_down, color: C.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(a.label.isNotEmpty ? a.label : s.nameForMac(a.mac, a.outlet),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    '${t('when_power')} ${a.above ? t('rises_above') : t('drops_below')} ${a.watts.toStringAsFixed(0)} W · ${fmtDuration(a.holdS)}',
                    style: TextStyle(fontSize: 12, color: C.textSoft),
                  ),
                  Text('${s.nameForMac(a.mac, a.outlet)} → ${_actText(a.act)}',
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
  const AutomationEditor({super.key, required this.state, this.initial});

  @override
  State<AutomationEditor> createState() => _AutomationEditorState();
}

class _AutomationEditorState extends State<AutomationEditor> {
  AppState get s => widget.state;
  late Automation a;
  late final TextEditingController _label, _watts;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    a = i != null ? Automation.fromJson(i.toJson()) : Automation(mac: s.allStrips.first.mac);
    _label = TextEditingController(text: a.label);
    _watts = TextEditingController(text: a.watts.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _label.dispose();
    _watts.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    a.label = _label.text.replaceAll('"', '').trim();
    a.watts = double.tryParse(_watts.text.trim()) ?? a.watts;
    setState(() => _saving = true);
    final ok = await s.saveAutomation(a);
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
      for (final o in st.outlets) {
        targets.add(MapEntry('${st.mac}|${o.n}', '${s.stripName(st)} · ${s.outletName(st, o.n)}'));
      }
    }
    final key = '${a.mac}|${a.outlet}';
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
                final p = v.split('|');
                setState(() {
                  a.mac = p[0];
                  a.outlet = int.parse(p[1]);
                });
              },
            ),
          ]),
          const SizedBox(height: 14),
          section(t('when_power'), [
            Segmented<bool>(
                value: a.above, items: {false: t('drops_below'), true: t('rises_above')}, onChanged: (v) => setState(() => a.above = v)),
            TextField(
              controller: _watts,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t('threshold'), suffixText: 'W'),
            ),
            Text(t('held_for'), style: TextStyle(color: C.muted, fontSize: 13)),
            DurationPicker(value: a.holdS, maxHours: 17, onChanged: (v) => setState(() => a.holdS = v < 5 ? 5 : v)),
          ]),
          const SizedBox(height: 14),
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
