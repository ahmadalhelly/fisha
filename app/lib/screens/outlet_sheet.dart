import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../services/outlet_history.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/link_card.dart';
import '../widgets/notion_icon_picker.dart';
import '../widgets/strip_card.dart' show timerText, timerIcon, guardedSwitch;
import 'automations_screen.dart' show AutomationEditor, AutomationsScreen, automationCondText;
import 'schedules_screen.dart' show daysText, dateText;


String _autoOffLabel(int m) => m == 0 ? t('auto_off_none') : fmtDuration(m * 60);

/// Strip-level sheet: name, every outlet, reboot all, device info.
void openStripSheet(BuildContext context, AppState state, String mac) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: state,
      builder: (ctx, _) {
        final s = state.live(mac);
        if (s == null) return const SizedBox(height: 120);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                Row(children: [
                  _iconButton(ctx, state.stripIcon(s.mac), (ico) => state.setStripIcon(s.mac, ico)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(state.stripName(s), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      Text(t('strip_settings'), style: TextStyle(color: C.muted)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),
                if (!s.online) ...[
                  emptyCard(t('offline_sheet'), icon: Icons.cloud_off),
                  const SizedBox(height: 8),
                ],
                if (state.can(Perm.prot))
                _tile(Icons.edit_outlined, t('rename_strip'), null, () async {
                  final v = await askName(ctx, t('strip_name'), state.stripName(s));
                  if (v != null) state.rename(s, 0, v);
                }),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.category_outlined, color: C.accent, size: 20),
                  ),
                  title: Text(Tr.isAr ? 'أيقونة المشترك' : 'Strip icon'),
                  subtitle: Text(
                    state.stripIcon(s.mac).isEmpty
                        ? (Tr.isAr ? 'بدون أيقونة' : 'None')
                        : (state.stripIcon(s.mac).startsWith('icon:')
                            ? state.stripIcon(s.mac).substring(5)
                            : state.stripIcon(s.mac)),
                    style: TextStyle(color: C.muted, fontSize: 12),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.stripIcon(s.mac).isNotEmpty) ...[
                        Container(
                          width: 34,
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: C.surface2,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: C.border),
                          ),
                          child: FishaIcon(icon: state.stripIcon(s.mac), size: 18),
                        ),
                        const SizedBox(width: 6),
                      ],
                      Icon(Icons.chevron_right, color: C.faint),
                    ],
                  ),
                  onTap: () => showNotionIconPicker(
                    context: ctx,
                    currentIcon: state.stripIcon(s.mac),
                    onSelected: (ico) => state.setStripIcon(s.mac, ico),
                  ),
                ),
                if (state.canAdmin)
                _tile(Icons.meeting_room_outlined, Tr.isAr ? 'الغرفة' : 'Room', state.roomForStrip(s.mac)?.name ?? (Tr.isAr ? 'بدون غرفة' : 'Unassigned'), () => _pickRoomDialog(ctx, state, s.mac)),
                if (state.canControl)
                _tile(Icons.restart_alt, t('cycle_strip'), t('cycle_sub'), !state.hubV2 || !s.online ? null : () => _cycleDialog(ctx, state, s, 0)),
                if (state.canControl)
                _tile(Icons.all_inclusive, t('loop'), t('loop_strip_sub'), !state.hubV2 || !s.online ? null : () => _loopDialog(ctx, state, s, 0)),
                if (state.can(Perm.auto))
                _tile(Icons.bolt, t('rule_cut'), t('rule_cut_strip_sub'), !state.hubV2 ? null : () => _openRule(ctx, state, s.mac, 0)),
                _switchTile(
                    Icons.fingerprint,
                    Tr.isAr ? 'بصمة للمفتاح الرئيسي' : 'Fingerprint for master switch',
                    Tr.isAr ? 'يطلب البصمة قبل تشغيل أو إيقاف المشترك كله' : 'Asks for fingerprint before switching the whole strip',
                    state.requiresBio(s.mac, 0),
                    true,
                    (v) => state.setRequiresBio(s.mac, 0, v)),
                if (state.can(Perm.prot))
                _switchTile(
                    Icons.lock_outline,
                    Tr.isAr ? 'قفل الأطفال للمشترك كله' : 'Child lock for the whole strip',
                    s.fw.contains('F1.0.82')
                        ? (Tr.isAr ? 'كل زراير المشترك نفسه (الرئيسي والمخارج) متشتغلش، والتطبيق شغال عادي' : 'Every button on the strip (master and outlets) stops working; the app still works')
                        : (Tr.isAr ? 'محتاج فيرموير المشترك F1.0.82 (حدّثه من مركز التحديثات)' : 'Needs strip firmware F1.0.82 (update it in the Update Center)'),
                    s.masterLock,
                    state.hubV2 && s.online && s.fw.contains('F1.0.82'),
                    (v) => state.setMasterLock(s, v)),
                if (state.canAdmin)
                _switchTile(Icons.notifications_outlined, t('notify_strip'), t('notify_strip_sub'), s.notifyMask & 0x10 != 0, state.hubV2,
                    (v) => state.setNotifyMask(s, v ? s.notifyMask | 0x10 : s.notifyMask & ~0x10)),
                const SizedBox(height: 8),
                Text(t('outlets'), style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
                for (final o in s.outlets)
                  _tile(
                    o.protected ? Icons.shield_outlined : Icons.power_outlined,
                    state.outletName(s, o.n),
                    [
                      o.on ? t('on_word') : t('off'),
                      if (state.requiresBio(s.mac, o.n)) (Tr.isAr ? 'بصمة' : 'Biometric'),
                      if (o.locked) t('child_lock'),
                      if (o.autoOffMin > 0) '${t('auto_off')} ${_autoOffLabel(o.autoOffMin)}',
                    ].join(' · '),
                    () => openOutletSheet(ctx, state, s.mac, o.n),
                  ),
                ..._timerList(ctx, state, state.timersFor(s.mac)),
                const SizedBox(height: 14),
                if (state.hubV2) LinkCard(state: state, mac: s.mac),
                Divider(color: C.border, height: 24),
                Text(t('device'), style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
                _info(Tr.isAr ? 'متصل من' : 'Connected since', s.online && s.upS != null ? formatHumanDuration(s.upS!) : '—'),
                _info(t('fw'), s.fw.isEmpty ? '—' : s.fw),
                _info(t('voltage'), s.voltage == null ? '—' : '${s.voltage!.toStringAsFixed(1)} V'),
                _info(Tr.isAr ? 'التيار الكلي' : 'Total current', s.online && s.voltage != null && s.voltage! > 0 ? '${(s.livePower / s.voltage!).toStringAsFixed(2)} A' : '—'),
                _info(t('rssi'), s.rssi == null ? '—' : '${s.rssi} dBm'),
                _info('IP', s.ip.isEmpty ? '—' : s.ip),
                if (state.showMac) _info('MAC', s.mac),
                Divider(color: C.border, height: 24),
                if (state.isOwner)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(color: C.danger.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                    child: Icon(Icons.delete_outline, color: C.danger, size: 20),
                  ),
                  title: Text(t('forget'), style: TextStyle(color: C.danger, fontWeight: FontWeight.w600)),
                  subtitle: Text(t('forget_sub'), style: TextStyle(color: C.muted, fontSize: 12)),
                  onTap: () async {
                    final name = state.stripName(s);
                    if (!await confirmDialog(ctx, t('forget'), t('forget_confirm', {'x': name}), ok: t('delete'), danger: true)) return;
                    final ok = await state.forget(s.mac);
                    if (ok && ctx.mounted) {
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${t('forget_ok')}: $name')));
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Outlet-level sheet: everything you can do with one outlet.
void openOutletSheet(BuildContext context, AppState state, String mac, int n) {
  showModalBottomSheet(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => ListenableBuilder(
      listenable: state,
      builder: (ctx, _) {
        final s = state.live(mac);
        if (s == null) return const SizedBox(height: 120);
        final o = s.outlets.firstWhere((x) => x.n == n, orElse: () => s.outlets.first);
        final v2 = state.hubV2 && s.online;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                Row(children: [
                  _iconButton(ctx, state.outletIcon(s.mac, n), (ico) => state.setOutletIcon(s.mac, n, ico)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(state.outletName(s, n), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      Text('${state.stripName(s)} · ${t('outlet_settings')}', style: TextStyle(color: C.muted)),
                    ]),
                  ),
                  Switch(
                    value: o.on,
                    // view members only look; control members leave protected outlets alone (hub 2.15.26 refuses it too)
                    onChanged: state.canControl && (!o.protected || state.can(Perm.prot)) ? (val) => guardedSwitch(ctx, state, s, o, val) : null,
                    activeTrackColor: C.accent,
                  ),
                ]),
                const SizedBox(height: 10),
                ..._linkedRules(ctx, state, s.mac, n, o.hasSchedule, o.hasRule),
                if (state.can(Perm.prot))
                _tile(Icons.edit_outlined, t('rename'), null, () async {
                  final v = await askName(ctx, t('outlet_name', {'n': n}), state.outletName(s, n));
                  if (v != null) state.rename(s, n, v);
                }),
                const SizedBox(height: 8),
                if (state.can(Perm.prot))
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: cardBox(radius: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.electric_meter_outlined, color: o.ampLimit > 0 ? C.warn : C.muted, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              Tr.isAr ? 'حد التيار (أمبير)' : 'Current limit (A)',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                          Text(
                            o.ampLimit <= 0 ? (Tr.isAr ? 'معطل' : 'Off') : '${o.ampLimit.toStringAsFixed(1)} A',
                            style: mono(14, color: o.ampLimit > 0 ? C.accent : C.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      ValueStepper(
                        value: o.ampLimit,
                        min: 0,
                        max: 16,
                        step: 0.5,
                        decimals: 1,
                        unit: 'A',
                        special: (v) => v <= 0 ? (Tr.isAr ? 'معطل' : 'Off') : null,
                        enabled: v2,
                        suggestion: _ampSuggestion(state, s, n),
                        suggestionNote: _ampSuggestionNote(state, s, n),
                        onChanged: (v) => state.setOutletAmpLimit(s.mac, n, v),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        Tr.isAr
                            ? (o.ampLimit <= 0 ? 'لا يوجد حد أقصى للتيار لهذا المخرج' : 'يفصل المخرج فور تجاوز ${o.ampLimit.toStringAsFixed(1)} أمبير لحماية الأجهزة')
                            : (o.ampLimit <= 0 ? 'No current limit set' : 'Trips outlet if current exceeds ${o.ampLimit.toStringAsFixed(1)} A'),
                        style: TextStyle(color: C.muted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (state.can(Perm.prot))
                _switchTile(Icons.shield_outlined, t('protect'), t('protect_sub'), o.protected, v2,
                    (v) => state.setProtected(s, n, v)),
                _switchTile(
                    Icons.fingerprint,
                    Tr.isAr ? 'يحتاج بصمة' : 'Require biometric',
                    Tr.isAr ? 'يطلب بصمة الإصبع قبل التشغيل أو الإيقاف' : 'Authenticate before switching',
                    state.requiresBio(s.mac, n),
                    true,
                    (v) => state.setRequiresBio(s.mac, n, v)),
                if (state.can(Perm.prot))
                _switchTile(Icons.lock_outline, t('child_lock'), t('child_lock_sub'), o.locked, state.hubHasConfig,
                    (v) => state.setLock(s, n, v)),
                if (state.can(Perm.prot))
                _switchTile(Icons.push_pin_outlined, t('keep_on'), t('keep_on_sub'), o.keepOn, state.hubHasConfig,
                    (v) => state.setKeepOn(s, n, v)),
                if (state.can(Perm.prot))
                _tile(
                    Icons.timer_outlined,
                    t('auto_off'),
                    o.autoOffInS >= 0
                        ? '${_autoOffLabel(o.autoOffMin)} · ${t('auto_off_left', {'x': fmtDuration(o.autoOffInS)})}'
                        : '${_autoOffLabel(o.autoOffMin)} — ${t('auto_off_sub')}',
                    !v2
                        ? null
                        : () async {
                            final sec = await durationDialog(ctx, t('auto_off'), (o.autoOffMin == 0 ? 30 : o.autoOffMin) * 60,
                                showSeconds: false, maxHours: 24, minSeconds: 60, hint: t('auto_off_sub'), clearLabel: t('auto_off_none'));
                            if (sec != null) state.setAutoOff(s, n, (sec ~/ 60).clamp(0, 1440));
                          }),
                if (state.canControl)
                _tile(Icons.hourglass_bottom, t('countdown'), t('countdown_sub'), !v2 ? null : () => _countdownDialog(ctx, state, s, n)),
                if (state.canControl)
                _tile(Icons.all_inclusive, t('loop'), t('loop_sub'), !v2 ? null : () => _loopDialog(ctx, state, s, n)),
                if (state.can(Perm.auto))
                _tile(Icons.bolt, t('rule_cut'), t('rule_cut_sub'), !v2 ? null : () => _openRule(ctx, state, s.mac, n)),
                if (state.canAdmin)
                _switchTile(Icons.notifications_outlined, t('notify_outlet'), t('notify_outlet_sub'), s.notifyMask & (1 << (n - 1)) != 0, v2,
                    (v) => state.setNotifyMask(s, v ? s.notifyMask | (1 << (n - 1)) : s.notifyMask & ~(1 << (n - 1)))),
                if (state.canControl)
                _tile(
                    Icons.restart_alt,
                    t('cycle'),
                    t('cycle_sub'),
                    !v2
                        ? null
                        : () {
                            if (o.protected) {
                              confirmDialog(ctx, t('cycle'), t('protected_cycle_block'));
                              return;
                            }
                            _cycleDialog(ctx, state, s, n);
                          }),
                ..._timerList(ctx, state, state.timersFor(s.mac, n)),
                if (!s.online) Padding(padding: const EdgeInsets.only(top: 8), child: emptyCard(t('offline_sheet'), icon: Icons.cloud_off))
                else if (!state.hubV2) Padding(padding: const EdgeInsets.only(top: 8), child: emptyCard(t('err_old_fw'))),
              ],
            ),
          ),
        );
      },
    ),
  );
}

/// Schedules and automations that act on this outlet (or on its whole strip). A tap opens the rule's page
/// and highlights it there.
bool _linkedLoading = false;
List<Widget> _linkedRules(BuildContext ctx, AppState state, String mac, int n, bool hasSched, bool hasRule) {
  bool mine(String m, int outlet) => m.toUpperCase() == mac.toUpperCase() && (outlet == n || outlet == 0);
  final scheds = state.schedules.where((x) => mine(x.mac, x.outlet)).toList();
  final rules = state.automations.where((x) => mine(x.mac, x.outlet)).toList();
  // the hub only flags that something exists; fetch the lists once if this phone hasn't yet
  if (!_linkedLoading && ((hasSched && scheds.isEmpty) || (hasRule && rules.isEmpty))) {
    _linkedLoading = true;
    Future.wait([if (hasSched && scheds.isEmpty) state.loadSchedules(), if (hasRule && rules.isEmpty) state.loadAutomations()])
        .whenComplete(() => _linkedLoading = false);
  }
  if (scheds.isEmpty && rules.isEmpty) return const [];
  Widget row(IconData icon, Color color, String title, String sub, bool enabled, VoidCallback onTap) => ListTile(
        dense: true,
        leading: Icon(icon, color: enabled ? color : C.faint),
        title: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: enabled ? C.text : C.muted)),
        subtitle: Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: C.muted)),
        trailing: Icon(Tr.isAr ? Icons.chevron_left : Icons.chevron_right, color: C.faint),
        onTap: onTap,
      );
  return [
    Padding(
      padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
      child: Text(t('linked_rules'), style: TextStyle(fontSize: 12, color: C.muted, fontWeight: FontWeight.w700)),
    ),
    Container(
      clipBehavior: Clip.antiAlias,
      decoration: cardBox(radius: 16),
      child: Column(children: [
        for (final sc in scheds)
          row(Icons.schedule, C.accent2, sc.label.isNotEmpty ? sc.label : t('linked_sched'),
              '${fmtTime12(sc.hh, sc.mm)} ${sc.on ? t('turn_on') : t('turn_off')} · ${sc.days == 0 ? dateText(sc.date) : daysText(sc.days)}', sc.enabled, () {
            final nav = Navigator.of(ctx);
            nav.popUntil((r) => r.isFirst);           // schedules are a home tab
            state.focusSid = sc.sid;
            state.setTab(1);
          }),
        for (final a in rules)
          row(Icons.bolt, C.warn, a.label.isNotEmpty ? a.label : t('linked_auto'), automationCondText(a), a.enabled, () {
            final nav = Navigator.of(ctx);
            nav.pop();
            state.focusAid = a.aid;
            nav.push(MaterialPageRoute(builder: (_) => AutomationsScreen(state: state)));
          }),
      ]),
    ),
    const SizedBox(height: 10),
  ];
}

void _openRule(BuildContext ctx, AppState state, String mac, int outlet) {
  Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => AutomationEditor(state: state, presetMac: mac, presetOutlet: outlet)));
}

List<Widget> _timerList(BuildContext ctx, AppState state, List<HubTimer> list) {
  if (list.isEmpty) return const [];
  return [
    const SizedBox(height: 8),
    Text(t('timers_active'), style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
    for (final x in list)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(timerIcon(x), color: C.accent),
        title: Text(state.nameForMac(x.mac, x.outlet)),
        subtitle: Text(timerText(x), style: TextStyle(color: C.muted)),
        trailing: TextButton(onPressed: () => state.cancelTimer(x.tid), child: Text(t('cancel_timer'), style: TextStyle(color: C.danger))),
      ),
    Text(t('timers_saved_note'), style: TextStyle(fontSize: 12, color: C.muted)),
  ];
}

Future<void> _countdownDialog(BuildContext ctx, AppState state, Strip s, int n) async {
  final o = s.outlets.firstWhere((x) => x.n == n);
  var on = !o.on;
  var delay = 30 * 60;
  var repeat = false;
  var every = 24 * 3600;
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setLocal) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(t('countdown'), style: const TextStyle(fontSize: 18)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('action'), style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Segmented<bool>(value: on, items: {true: t('turn_on'), false: t('turn_off')}, onChanged: (v) => setLocal(() => on = v)),
          const SizedBox(height: 14),
          Text(t('start_after'), style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 6),
          DurationPicker(value: delay, onChanged: (v) => setLocal(() => delay = v)),
          if (delay < 5) ...[const SizedBox(height: 8), Text(t('dur_min', {'x': fmtDuration(5)}), style: TextStyle(color: C.danger, fontSize: 12))],
          const SizedBox(height: 14),
          _repeatPicker(repeat, every, (r) => setLocal(() => repeat = r), (v) => setLocal(() => every = v)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: delay < 5 || (repeat && every < 60) ? null : () => Navigator.pop(dctx, true), child: Text(t('save'))),
        ],
      ),
    ),
  );
  if (ok != true || !ctx.mounted) return;
  if (!on && o.protected) {
    final sure = await confirmDialog(ctx, t('confirm_off_t', {'x': state.outletName(s, n)}), t('confirm_off_b'), danger: true);
    if (!sure) return;
  }
  await state.addTimer(s.mac, n, on ? 'on' : 'off', delayS: delay, repeatS: repeat ? every : 0);
}

/// Power-cycle every strip of a room at once (whole strips, outlet 0).
Future<void> roomCycleDialog(BuildContext ctx, AppState state, List<Strip> strips, String roomName) =>
    _cycleDialog(ctx, state, strips.first, 0, room: strips, roomName: roomName);

/// Start the same on/off loop on every strip of a room.
Future<void> roomLoopDialog(BuildContext ctx, AppState state, List<Strip> strips, String roomName) =>
    _loopDialog(ctx, state, strips.first, 0, room: strips, roomName: roomName);

Future<void> _cycleDialog(BuildContext ctx, AppState state, Strip s, int n, {List<Strip>? room, String? roomName}) async {
  final targets = room ?? [s];
  if (n == 0 && targets.any((x) => x.outlets.any((o) => o.protected))) {
    await confirmDialog(ctx, t('cycle_strip'), t('protected_cycle_block'));
    return;
  }
  var off = 10;
  var delay = 300;
  var later = false;
  var repeat = false;
  var every = 24 * 3600;
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setLocal) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(roomName != null ? '${t('cycle')} · $roomName' : (n == 0 ? t('cycle_strip') : '${t('cycle')} · ${state.outletName(s, n)}'), style: const TextStyle(fontSize: 18)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('cycle_off_for'), style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 6),
          DurationPicker(value: off, showHours: false, onChanged: (v) => setLocal(() => off = v)),
          if (off < 3) ...[const SizedBox(height: 8), Text(t('dur_min', {'x': fmtDuration(3)}), style: TextStyle(color: C.danger, fontSize: 12))],
          const SizedBox(height: 16),
          Text(t('start_after'), style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 6),
          Segmented<bool>(value: later, items: {false: t('now'), true: t('later')}, onChanged: (v) => setLocal(() => later = v)),
          if (later) ...[const SizedBox(height: 10), DurationPicker(value: delay, onChanged: (v) => setLocal(() => delay = v))],
          const SizedBox(height: 14),
          _repeatPicker(repeat, every, (r) => setLocal(() => repeat = r), (v) => setLocal(() => every = v)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: off < 3 || (repeat && every <= off) ? null : () => Navigator.pop(dctx, true), child: Text(t('confirm'))),
        ],
      ),
    ),
  );
  if (ok != true) return;
  for (final x in targets) {
    await state.addTimer(x.mac, n, 'cycle', delayS: later ? delay : 0, offS: off, repeatS: repeat ? every : 0);
  }
}

Widget _repeatPicker(bool repeat, int every, ValueChanged<bool> onRepeat, ValueChanged<int> onEvery) =>
    Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('repeat'), style: TextStyle(color: C.muted, fontSize: 13)),
      const SizedBox(height: 6),
      Segmented<bool>(value: repeat, items: {false: t('once'), true: t('repeat_forever')}, onChanged: onRepeat),
      if (repeat) ...[
        const SizedBox(height: 10),
        Text(t('repeat_each'), style: TextStyle(color: C.muted, fontSize: 12)),
        const SizedBox(height: 6),
        DurationPicker(value: every, showSeconds: false, maxHours: 167, onChanged: onEvery),
      ],
    ]);

Future<void> _loopDialog(BuildContext ctx, AppState state, Strip s, int n, {List<Strip>? room, String? roomName}) async {
  final targets = room ?? [s];
  if (n == 0 ? targets.any((x) => x.outlets.any((o) => o.protected)) : s.outlets.firstWhere((x) => x.n == n).protected) {
    await confirmDialog(ctx, t('loop'), t('protected_cycle_block'));
    return;
  }
  var onS = 3600;
  var offS = 3600;
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setLocal) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(roomName != null ? '${t('loop')} · $roomName' : (n == 0 ? '${t('loop')} · ${t('whole_strip')}' : '${t('loop')} · ${state.outletName(s, n)}'), style: const TextStyle(fontSize: 18)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('loop_hint'), style: TextStyle(color: C.muted, fontSize: 12, height: 1.5)),
          const SizedBox(height: 12),
          Text(t('loop_on_for'), style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 6),
          DurationPicker(value: onS, maxHours: 72, onChanged: (v) => setLocal(() => onS = v)),
          const SizedBox(height: 12),
          Text(t('loop_off_for'), style: TextStyle(color: C.muted, fontSize: 13)),
          const SizedBox(height: 6),
          DurationPicker(value: offS, maxHours: 72, onChanged: (v) => setLocal(() => offS = v)),
          if (onS < 10 || offS < 10) ...[const SizedBox(height: 8), Text(t('dur_min', {'x': fmtDuration(10)}), style: TextStyle(color: C.danger, fontSize: 12))],
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: onS < 10 || offS < 10 ? null : () => Navigator.pop(dctx, true), child: Text(t('loop_start'))),
        ],
      ),
    ),
  );
  if (ok != true) return;
  for (final x in targets) {
    await state.addTimer(x.mac, n, 'loop', onS: onS, offS: offS);
  }
}

Widget _tile(IconData icon, String title, String? sub, VoidCallback? onTap) => ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: onTap != null,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: onTap == null ? C.faint : C.accent, size: 20),
      ),
      title: Text(title),
      subtitle: sub == null || sub.isEmpty ? null : Text(sub, style: TextStyle(color: C.muted, fontSize: 12)),
      trailing: onTap == null ? null : Icon(Icons.chevron_right, color: C.faint),
      onTap: onTap,
    );

Widget _switchTile(IconData icon, String title, String sub, bool value, bool enabled, ValueChanged<bool> onChanged) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: C.accentBg, borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: enabled ? C.accent : C.faint, size: 20),
      ),
      title: Text(title),
      subtitle: Text(sub, style: TextStyle(color: C.muted, fontSize: 12)),
      trailing: Switch(value: value, onChanged: enabled ? onChanged : null, activeTrackColor: C.accent),
      onTap: enabled ? () => onChanged(!value) : null,
    );

Widget _info(String k, String v) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text(k, style: TextStyle(color: C.muted)),
        const Spacer(),
        Text(v, textDirection: TextDirection.ltr, style: mono(13, color: C.textSoft, weight: FontWeight.w500)),
      ]),
    );

Future<void> _pickRoomDialog(BuildContext ctx, AppState state, String mac) async {
  if (state.rooms.isEmpty) {
    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(Tr.isAr ? 'ضيف غرف الأول من الإعدادات' : 'Create rooms first in Settings')));
    return;
  }
  final current = state.roomForStrip(mac);
  await showDialog<void>(
    context: ctx,
    builder: (dCtx) => AlertDialog(
      backgroundColor: C.surface,
      title: Text(Tr.isAr ? 'اختيار الغرفة' : 'Select Room', style: const TextStyle(fontSize: 18)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(Tr.isAr ? 'بدون غرفة' : 'Unassigned'),
              trailing: current == null ? Icon(Icons.check, color: C.accent) : null,
              onTap: () {
                state.assignStripToRoom(mac, null);
                Navigator.pop(dCtx);
              },
            ),
            for (final r in state.rooms)
              ListTile(
                title: Text(r.name),
                trailing: current?.id == r.id ? Icon(Icons.check, color: C.accent) : null,
                onTap: () {
                  state.assignStripToRoom(mac, r.id);
                  Navigator.pop(dCtx);
                },
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dCtx), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
      ],
    ),
  );
}

/// The icon next to a strip or outlet name in its sheet: tap it to pick another one.
Widget _iconButton(BuildContext ctx, String icon, ValueChanged<String> onSelected) => InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _pickIconDialog(ctx, onSelected, icon),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: C.surface2, borderRadius: BorderRadius.circular(14), border: Border.all(color: C.border)),
        child: icon.isEmpty ? Icon(Icons.add_reaction_outlined, color: C.muted) : FishaIcon(icon: icon, size: 24),
      ),
    );

Future<void> _pickIconDialog(BuildContext ctx, ValueChanged<String> onSelected, [String current = '']) =>
    showNotionIconPicker(context: ctx, currentIcon: current, onSelected: onSelected);


/// Highest current this outlet drew in the last 30 days (recorded by the app), or null if nothing yet.
double? _peakAmps(Strip s, int n) {
  final h = OutletHistory.instance;
  final since = OutletHistory.dayKey(DateTime.now().subtract(const Duration(days: 30)));
  final p = h.peakOver(h.dates.where((d) => d >= since), s.mac, n);
  if (p == null || p.peakW < 5) return null;
  final v = (s.voltage ?? 230) < 150 ? 230.0 : (s.voltage ?? 230).toDouble();
  return p.peakW / v;
}

/// Smart limit: about 40% above the highest draw seen, rounded up to half an amp.
double? _ampSuggestion(AppState state, Strip s, int n) {
  final a = _peakAmps(s, n);
  if (a == null) return null;
  return ((a * 1.4 * 2).ceil() / 2).clamp(1.0, 16.0).toDouble();
}

String? _ampSuggestionNote(AppState state, Strip s, int n) {
  final a = _peakAmps(s, n);
  if (a == null) return null;
  return Tr.isAr ? 'أعلى سحب اتسجل آخر 30 يوم ${a.toStringAsFixed(1)} A، والحد أعلى منه بحوالي 40%' : 'Highest draw in 30 days: ${a.toStringAsFixed(1)} A, limit set about 40% above it';
}
