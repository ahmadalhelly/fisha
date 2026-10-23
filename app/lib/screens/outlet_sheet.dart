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
import 'outlet_log_screen.dart';

part 'outlet_sheet/dialogs.dart';

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
                _tile(Icons.history, Tr.isAr ? 'سجل التشغيل' : 'On/off history', Tr.isAr ? 'كل الدورات واستهلاكها' : 'Every cycle and its energy', !state.hubV2 ? null : () => _openLog(ctx, state, s.mac, 0)),
                if (state.can(Perm.auto))
                _tile(Icons.bolt, t('rule_cut'), t('rule_cut_strip_sub'), !state.hubV2 ? null : () => _openRule(ctx, state, s.mac, 0)),
                // the schedules and rules on the whole strip, like an outlet lists its own
                ..._linkedRules(ctx, state, s.mac, 0, s.hasSchedule, s.hasRule),
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
                    stripFwHasChildLock(s.fw)
                        ? (Tr.isAr ? 'كل زراير المشترك نفسه (الرئيسي والمخارج) متشتغلش، والتطبيق شغال عادي' : 'Every button on the strip (master and outlets) stops working; the app still works')
                        : (Tr.isAr ? 'محتاج فيرموير المشترك F1.0.82 (حدّثه من مركز التحديثات)' : 'Needs strip firmware F1.0.82 (update it in the Update Center)'),
                    s.masterLock,
                    state.hubV2 && s.online && stripFwHasChildLock(s.fw),
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
                    // view members only look; control members leave protected outlets alone (refuses it too)
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
                _tile(Icons.history, Tr.isAr ? 'سجل التشغيل' : 'On/off history', Tr.isAr ? 'الدورات والاستهلاك والتكلفة' : 'Cycles, energy and cost', !v2 ? null : () => _openLog(ctx, state, s.mac, n)),
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

/// strip firmware F1.0.82 or newer (F1.0.83, F1.1.0, F2.0.0 ...) has the physical child lock
bool stripFwHasChildLock(String fw) {
  final m = RegExp(r'F(\d+)\.(\d+)\.(\d+)').firstMatch(fw);
  if (m == null) return false;
  final v = [for (var i = 1; i <= 3; i++) int.parse(m.group(i)!)];
  if (v[0] != 1) return v[0] > 1;
  if (v[1] != 0) return v[1] > 0;
  return v[2] >= 82;
}
