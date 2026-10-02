import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/strip_card.dart' show timerText, guardedSwitch;


String _autoOffLabel(int m) => m == 0 ? t('auto_off_none') : fmtDuration(m * 60);

/// Strip-level sheet: name, every outlet, power-cycle all, device info.
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
                Text(state.stripName(s), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                Text(t('strip_settings'), style: TextStyle(color: C.muted)),
                const SizedBox(height: 12),
                _tile(Icons.edit_outlined, t('rename_strip'), null, () async {
                  final v = await askName(ctx, t('strip_name'), state.stripName(s));
                  if (v != null) state.rename(s, 0, v);
                }),
                _tile(Icons.restart_alt, t('cycle_strip'), t('cycle_sub'), !state.hubV2 ? null : () => _cycleDialog(ctx, state, s, 0)),
                const SizedBox(height: 8),
                Text(t('outlets'), style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
                for (final o in s.outlets)
                  _tile(
                    o.protected ? Icons.shield_outlined : Icons.power_outlined,
                    state.outletName(s, o.n),
                    [
                      o.on ? t('on_word') : t('off'),
                      if (o.locked) t('child_lock'),
                      if (o.autoOffMin > 0) '${t('auto_off')} ${_autoOffLabel(o.autoOffMin)}',
                    ].join(' · '),
                    () => openOutletSheet(ctx, state, s.mac, o.n),
                  ),
                ..._timerList(ctx, state, state.timersFor(s.mac)),
                Divider(color: C.border, height: 24),
                Text(t('device'), style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
                _info(t('fw'), s.fw.isEmpty ? '—' : s.fw),
                _info(t('voltage'), s.voltage == null ? '—' : '${s.voltage!.toStringAsFixed(1)} V'),
                _info(t('rssi'), s.rssi == null ? '—' : '${s.rssi} dBm'),
                if (state.showMac) _info('MAC', s.mac),
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
        final v2 = state.hubV2;
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(state.outletName(s, n), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                      Text('${state.stripName(s)} · ${t('outlet_settings')}', style: TextStyle(color: C.muted)),
                    ]),
                  ),
                  Switch(
                    value: o.on,
                    onChanged: (val) => guardedSwitch(ctx, state, s, o, val),
                    activeTrackColor: C.accent,
                  ),
                ]),
                const SizedBox(height: 10),
                _tile(Icons.edit_outlined, t('rename'), null, () async {
                  final v = await askName(ctx, t('outlet_name', {'n': n}), state.outletName(s, n));
                  if (v != null) state.rename(s, n, v);
                }),
                _switchTile(Icons.shield_outlined, t('protect'), t('protect_sub'), o.protected, v2,
                    (v) => state.setProtected(s, n, v)),
                _switchTile(Icons.lock_outline, t('child_lock'), t('child_lock_sub'), o.locked, state.hubHasConfig,
                    (v) => state.setLock(s, n, v)),
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
                _tile(Icons.hourglass_bottom, t('countdown'), t('countdown_sub'), !v2 ? null : () => _countdownDialog(ctx, state, s, n)),
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
                if (!v2) Padding(padding: const EdgeInsets.only(top: 8), child: emptyCard(t('err_old_fw'))),
              ],
            ),
          ),
        );
      },
    ),
  );
}

List<Widget> _timerList(BuildContext ctx, AppState state, List<HubTimer> list) {
  if (list.isEmpty) return const [];
  return [
    const SizedBox(height: 8),
    Text(t('timers_active'), style: TextStyle(fontSize: 13, color: C.muted, fontWeight: FontWeight.w600)),
    for (final x in list)
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(x.kind == 'cycle' ? Icons.restart_alt : Icons.hourglass_bottom, color: C.accent),
        title: Text(state.nameForMac(x.mac, x.outlet)),
        subtitle: Text(timerText(x), style: TextStyle(color: C.muted)),
        trailing: TextButton(onPressed: () => state.cancelTimer(x.tid), child: Text(t('cancel_timer'), style: TextStyle(color: C.danger))),
      ),
    Text(t('timers_ram_note'), style: TextStyle(fontSize: 12, color: C.muted)),
  ];
}

Future<void> _countdownDialog(BuildContext ctx, AppState state, Strip s, int n) async {
  final o = s.outlets.firstWhere((x) => x.n == n);
  var on = !o.on;
  var delay = 30 * 60;
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
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: delay < 5 ? null : () => Navigator.pop(dctx, true), child: Text(t('save'))),
        ],
      ),
    ),
  );
  if (ok != true || !ctx.mounted) return;
  if (!on && o.protected) {
    final sure = await confirmDialog(ctx, t('confirm_off_t', {'x': state.outletName(s, n)}), t('confirm_off_b'), danger: true);
    if (!sure) return;
  }
  await state.addTimer(s.mac, n, on ? 'on' : 'off', delayS: delay);
}

Future<void> _cycleDialog(BuildContext ctx, AppState state, Strip s, int n) async {
  if (n == 0 && s.outlets.any((o) => o.protected)) {
    await confirmDialog(ctx, t('cycle_strip'), t('protected_cycle_block'));
    return;
  }
  var off = 10;
  var delay = 300;
  var later = false;
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (dctx) => StatefulBuilder(
      builder: (dctx, setLocal) => AlertDialog(
        backgroundColor: C.surface,
        title: Text(n == 0 ? t('cycle_strip') : '${t('cycle')} · ${state.outletName(s, n)}', style: const TextStyle(fontSize: 18)),
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
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(onPressed: off < 3 ? null : () => Navigator.pop(dctx, true), child: Text(t('confirm'))),
        ],
      ),
    ),
  );
  if (ok == true) await state.addTimer(s.mac, n, 'cycle', delayS: later ? delay : 0, offS: off);
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
