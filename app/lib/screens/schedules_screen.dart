import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'outlet_sheet.dart';

// Sunday-first, matching the hub's bit order (bit 0 = Sunday).
List<String> get _dayShort => Tr.isAr ? const ['ح', 'ن', 'ث', 'ر', 'خ', 'ج', 'س'] : const ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
List<String> get _dayLong => Tr.isAr
    ? const ['الأحد', 'الاتنين', 'التلات', 'الأربع', 'الخميس', 'الجمعة', 'السبت']
    : const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

String daysText(int days) {
  if (days == 0x7F) return t('every_day');
  return [for (var i = 0; i < 7; i++) if (days & (1 << i) != 0) _dayLong[i]].join('، ');
}

String dateText(int d) => d == 0 ? '—' : '${d % 100}/${(d ~/ 100) % 100}/${d ~/ 10000}';

class SchedulesScreen extends StatefulWidget {
  final AppState state;
  const SchedulesScreen({super.key, required this.state});

  @override
  State<SchedulesScreen> createState() => _SchedulesScreenState();
}

class _SchedulesScreenState extends State<SchedulesScreen> {
  AppState get s => widget.state;
  bool _loading = false;
  int _lastTab = -1;

  Future<void> _load() async {
    if (!s.hubV2) return;
    setState(() => _loading = true);
    await s.loadSchedules();
    if (mounted) setState(() => _loading = false);
  }

  void _edit([Schedule? sc]) {
    if (s.allStrips.isEmpty) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScheduleEditor(state: s, initial: sc)));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        if (s.tab == 1 && _lastTab != 1) WidgetsBinding.instance.addPostFrameCallback((_) => _load());
        if (s.focusSid != 0) WidgetsBinding.instance.addPostFrameCallback((_) => s.focusSid = 0);
        _lastTab = s.tab;
        return Scaffold(
          backgroundColor: C.tabBg,
          floatingActionButton: s.hubV2 && s.allStrips.isNotEmpty && s.canControl
              ? Padding(
                  padding: EdgeInsets.only(bottom: fabLift(context)),
                  child: SizedBox(
                    height: 44,
                    child: FloatingActionButton.extended(
                      onPressed: () => _edit(),
                      elevation: 4,
                      backgroundColor: C.accent,
                      foregroundColor: C.onAccent,
                      icon: const Icon(Icons.add_alarm, size: 20),
                      label: Text(t('sched_new'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    ),
                  ),
                )
              : null,
          body: SafeArea(
            bottom: false,
            child: RefreshIndicator(
              color: C.accent,
              onRefresh: _load,
              child: ListView(cacheExtent: 4000, padding: EdgeInsets.fromLTRB(18, 20, 18, navInset(context) + 76), children: [
                Text(t('sched_title'), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                if (!s.hubV2)
                  emptyCard(t('err_old_fw'))
                else ...[
                  if (!s.hubTimeOk) Padding(padding: const EdgeInsets.only(bottom: 12), child: emptyCard(t('need_time'), icon: Icons.schedule)),
                  if (_loading && s.schedules.isEmpty) Center(child: CircularProgressIndicator(color: C.accent)),
                  if (!_loading && s.schedules.isEmpty) emptyCard(t('sched_empty'), icon: Icons.alarm),
                  for (final sc in s.schedules)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FocusFlash(active: s.focusSid != 0 && s.focusSid == sc.sid, child: _card(sc)),
                    ),
                ],
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _card(Schedule sc) {
    return Material(
      color: C.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: C.cardEdge)),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: s.canControl ? () => _edit(sc) : null,
        onLongPress: s.canControl ? () => _menu(sc) : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(fmtTime12(sc.hh, sc.mm), style: mono(24, color: sc.enabled ? C.text : C.faint)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: sc.on ? C.accentBg : C.surface2, borderRadius: BorderRadius.circular(999)),
                child: Text(sc.on ? t('turn_on') : t('turn_off'), style: TextStyle(fontSize: 11, color: sc.on ? C.accent : C.muted)),
              ),
            ]),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(sc.label.isNotEmpty ? sc.label : s.nameForMac(sc.mac, sc.outlet),
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  // the whole strip or one outlet, readable at a glance
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: sc.outlet == 0 ? C.accent.withValues(alpha: 0.16) : C.surface2, borderRadius: BorderRadius.circular(99)),
                    child: Text(sc.outlet == 0 ? (Tr.isAr ? 'المشترك كله' : 'Whole strip') : (Tr.isAr ? 'مخرج' : 'Outlet'),
                        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: sc.outlet == 0 ? C.accent : C.muted)),
                  ),
                ]),
                if (sc.label.isNotEmpty)
                  Text(s.nameForMac(sc.mac, sc.outlet), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
                const SizedBox(height: 4),
                Text(sc.days == 0 ? '${t('once')} · ${dateText(sc.date)}' : daysText(sc.days),
                    maxLines: 2, style: TextStyle(fontSize: 12, color: C.textSoft)),
                if (sc.skip) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.skip_next, size: 14, color: C.warn),
                    const SizedBox(width: 3),
                    Text(t('sched_skipped'), style: TextStyle(fontSize: 11.5, color: C.warn, fontWeight: FontWeight.w600)),
                  ]),
                ],
              ]),
            ),
            Switch(
              value: sc.enabled,
              activeTrackColor: C.accent,
              onChanged: (v) {
                sc.enabled = v;
                s.saveSchedule(sc);
              },
            ),
          ]),
        ),
      ),
    );
  }

  /// Long-press on a schedule: run now, pause, skip the next run, edit, duplicate, open the outlet, delete.
  Future<void> _menu(Schedule sc) async {
    final name = sc.label.isNotEmpty ? sc.label : s.nameForMac(sc.mac, sc.outlet);
    Widget item(String key, IconData icon, String title, {String? sub, bool danger = false}) => ListTile(
          leading: Icon(icon, color: danger ? C.danger : C.accent),
          title: Text(title, style: danger ? TextStyle(color: C.danger) : null),
          subtitle: sub == null ? null : Text(sub, style: TextStyle(fontSize: 12, color: C.muted)),
          onTap: () => Navigator.pop(context, key),
        );
    final pending = sc.sid <= 0;                 // still waiting on this phone for the hub
    final act = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: C.surface,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
              child: Text('${fmtTime12(sc.hh, sc.mm)} · ${sc.on ? t('turn_on') : t('turn_off')}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.5, color: C.muted)),
            ),
            item('run', Icons.play_arrow_rounded, t('sched_run_now'), sub: sc.on ? t('sched_run_on') : t('sched_run_off')),
            item('toggle', sc.enabled ? Icons.pause_circle_outline : Icons.play_circle_outline, sc.enabled ? t('sched_pause') : t('sched_resume'),
                sub: sc.enabled ? t('sched_pause_sub') : t('sched_resume_sub')),
            if (!pending && sc.enabled)
              item('skip', Icons.skip_next_outlined, sc.skip ? t('sched_unskip') : t('sched_skip'), sub: sc.skip ? null : t('sched_skip_sub')),
            Divider(height: 12, indent: 20, endIndent: 20, color: C.border),
            item('edit', Icons.edit_outlined, Tr.isAr ? 'تعديل' : 'Edit'),
            item('dup', Icons.copy_all_outlined, Tr.isAr ? 'نسخة' : 'Duplicate'),
            item('outlet', Icons.power_outlined, t('sched_go_outlet')),
            Divider(height: 12, indent: 20, endIndent: 20, color: C.border),
            item('del', Icons.delete_outline, t('delete'), danger: true),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
    if (!mounted || act == null) return;
    switch (act) {
      case 'run':
        await s.runScheduleNow(sc);
      case 'toggle':
        sc.enabled = !sc.enabled;
        await s.saveSchedule(sc);
      case 'skip':
        await s.skipNextSchedule(sc, !sc.skip);
      case 'edit':
        _edit(sc);
      case 'dup':
        final copy = Schedule.fromJson(sc.toJson())
          ..sid = 0
          ..skip = false
          ..label = sc.label.isEmpty ? '' : '${sc.label} (${Tr.isAr ? 'نسخة' : 'copy'})';
        await s.saveSchedule(copy);
      case 'outlet':
        if (sc.outlet == 0) {
          openStripSheet(context, s, sc.mac);
        } else {
          openOutletSheet(context, s, sc.mac, sc.outlet);
        }
      case 'del':
        if (!await confirmDialog(context, t('delete'), name, ok: t('delete'), danger: true)) return;
        await s.deleteSchedule(sc.sid);
    }
  }
}

class ScheduleEditor extends StatefulWidget {
  final AppState state;
  final Schedule? initial;
  final String? presetRoom;
  const ScheduleEditor({super.key, required this.state, this.initial, this.presetRoom});

  @override
  State<ScheduleEditor> createState() => _ScheduleEditorState();
}

class _ScheduleEditorState extends State<ScheduleEditor> {
  AppState get s => widget.state;
  late Schedule sc;
  late final TextEditingController _label;
  bool _saving = false;
  // new schedules can be an on + off pair ("تشغيل وإيقاف")
  int _mode = 0; // 0 = off, 1 = on, 2 = on then off
  TimeOfDay _offAt = const TimeOfDay(hour: 23, minute: 0);
  String? _roomId;

  List<String> get _roomMacs {
    final r = s.rooms.where((x) => x.id == _roomId).firstOrNull;
    return r == null ? const [] : r.stripMacs.where((m) => s.allStrips.any((st) => st.mac == m)).toList();
  }

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    sc = i != null
        ? Schedule.fromJson(i.toJson())
        : Schedule(mac: s.allStrips.first.mac, outlet: 1, on: false, days: 0x7F, hh: 23, mm: 0);
    _label = TextEditingController(text: sc.label);
    _mode = sc.on ? 1 : 0;
    if (i == null) {
      sc.hh = 18;
      sc.on = true;
      _mode = 2;
      _roomId = widget.presetRoom;
      if (_roomMacs.isNotEmpty) {
        sc.mac = _roomMacs.first;
        sc.outlet = 0;
      } else {
        _roomId = null;
      }
    }
  }

  @override
  void dispose() {
    _label.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (sc.days == 0 && sc.date == 0) {
      final n = DateTime.now();
      sc.date = n.year * 10000 + n.month * 100 + n.day;
    }
    sc.label = _label.text.replaceAll('"', '').trim();
    setState(() => _saving = true);
    sc.on = _mode != 0;
    var ok = true;
    for (final mac in _roomId != null ? _roomMacs : [sc.mac]) {
      final one = Schedule.fromJson(sc.toJson())..mac = mac;
      if (_roomId != null && one.label.isEmpty) one.label = s.rooms.firstWhere((r) => r.id == _roomId).name;
      ok = await s.saveSchedule(one) && ok;
      if (ok && _mode == 2 && widget.initial == null) {
        final off = Schedule.fromJson(one.toJson())
          ..sid = 0
          ..on = false
          ..hh = _offAt.hour
          ..mm = _offAt.minute;
        ok = await s.saveSchedule(off) && ok;
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) Navigator.of(context).pop();
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, t('delete'), t('sched_edit'), ok: t('delete'), danger: true)) return;
    await s.deleteSchedule(sc.sid);
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
    final key = _roomId != null ? 'room:$_roomId|0' : '${sc.mac}|${sc.outlet}';
    final weekly = sc.days != 0;
    return Scaffold(
      backgroundColor: C.bg,
      appBar: AppBar(
        backgroundColor: C.bg,
        surfaceTintColor: Colors.transparent,
        title: Text(widget.initial == null ? t('sched_new') : t('sched_edit'), style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (widget.initial != null) IconButton(onPressed: _delete, icon: Icon(Icons.delete_outline, color: C.danger)),
        ],
      ),
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
          InkWell(
            borderRadius: BorderRadius.circular(22),
            onTap: () async {
              final p = await pickTime12(context, TimeOfDay(hour: sc.hh, minute: sc.mm));
              if (p != null) {
                setState(() {
                  sc.hh = p.hour;
                  sc.mm = p.minute;
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 22),
              decoration: cardBox(),
              alignment: Alignment.center,
              child: Column(children: [
                Text(_mode == 2 ? t('on_at') : t('time'), style: TextStyle(color: C.muted, fontSize: 13)),
                const SizedBox(height: 6),
                Text(fmtTime12(sc.hh, sc.mm), style: mono(40, color: C.accent)),
              ]),
            ),
          ),
          const SizedBox(height: 14),
          if (_mode == 2) ...[
            InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () async {
                final p = await pickTime12(context, _offAt);
                if (p != null) setState(() => _offAt = p);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 18),
                decoration: cardBox(),
                alignment: Alignment.center,
                child: Column(children: [
                  Text(t('off_at'), style: TextStyle(color: C.muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  Text(fmtTime12(_offAt.hour, _offAt.minute), style: mono(32, color: C.textSoft)),
                ]),
              ),
            ),
            const SizedBox(height: 14),
          ],
          section(t('action'), [
            Segmented<int>(
              value: _mode,
              items: {
                1: t('turn_on'),
                0: t('turn_off'),
                if (widget.initial == null) 2: t('on_and_off'),
              },
              onChanged: (v) => setState(() => _mode = v),
            ),
          ]),
          const SizedBox(height: 14),
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
                    sc.mac = r.stripMacs.firstWhere((m) => s.allStrips.any((st) => st.mac == m));
                    sc.outlet = 0;
                  });
                  return;
                }
                _roomId = null;
                final parts = v.split('|');
                setState(() {
                  sc.mac = parts[0];
                  sc.outlet = int.parse(parts[1]);
                });
              },
            ),
          ]),
          const SizedBox(height: 14),
          section(t('sched_repeat'), [
            Segmented<bool>(
              value: weekly,
              items: {true: t('weekly'), false: t('once')},
              onChanged: (v) => setState(() {
                if (v) {
                  sc.days = 0x7F;
                } else {
                  sc.days = 0;
                  final n = DateTime.now();
                  sc.date = n.year * 10000 + n.month * 100 + n.day;
                }
              }),
            ),
            if (weekly)
              Row(children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(999),
                        onTap: () => setState(() {
                          final nd = sc.days ^ (1 << i);
                          if (nd != 0) sc.days = nd;
                        }),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          height: 40,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: sc.days & (1 << i) != 0 ? C.accent : C.surface2,
                          ),
                          child: Text(_dayShort[i],
                              style: TextStyle(fontWeight: FontWeight.w700, color: sc.days & (1 << i) != 0 ? C.onAccent : C.muted)),
                        ),
                      ),
                    ),
                  ),
              ])
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.event, color: C.accent),
                title: Text(t('date')),
                trailing: Text(dateText(sc.date), textDirection: TextDirection.ltr, style: mono(14)),
                onTap: () async {
                  final now = DateTime.now();
                  final init = sc.date == 0 ? now : DateTime(sc.date ~/ 10000, (sc.date ~/ 100) % 100, sc.date % 100);
                  final d = await showDatePicker(
                    context: context,
                    initialDate: init.isBefore(now) ? now : init,
                    firstDate: DateTime(now.year, now.month, now.day),
                    lastDate: now.add(const Duration(days: 365)),
                  );
                  if (d != null) setState(() => sc.date = d.year * 10000 + d.month * 100 + d.day);
                },
              ),
          ]),
          const SizedBox(height: 14),
          section(t('label_opt'), [
            TextField(controller: _label, maxLength: 30, decoration: InputDecoration(hintText: t('sched_label_hint'))),
          ]),
          const SizedBox(height: 16),
          primaryButton(t('save'), _saving ? null : _save, icon: Icons.check),
        ]),
      ),
    );
  }
}
