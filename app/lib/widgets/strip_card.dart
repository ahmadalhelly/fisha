import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../screens/outlet_sheet.dart';
import '../theme.dart';

/// Switch an outlet, asking first if it is protected and being turned off.
Future<void> guardedSwitch(BuildContext context, AppState state, Strip s, Outlet o, bool on) async {
  if (!on && o.protected) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        icon: Icon(Icons.shield_outlined, color: C.accent),
        title: Text(t('confirm_off_t', {'x': state.outletName(s, o.n)}), style: const TextStyle(fontSize: 18)),
        content: Text(t('confirm_off_b'), style: TextStyle(color: C.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(t('turn_off'), style: TextStyle(color: C.danger, fontWeight: FontWeight.w700))),
        ],
      ),
    );
    if (ok != true) return;
  }
  await state.setOutlet(s.mac, o.n, on);
}

Future<void> guardedAllOff(BuildContext context, AppState state, Strip s) async {
  if (!s.anyProtectedOn) return state.setOutlet(s.mac, 0, false);
  final names = s.outlets.where((o) => o.protected && o.on).map((o) => state.outletName(s, o.n)).join('، ');
  final choice = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: C.surface,
      icon: Icon(Icons.shield_outlined, color: C.accent),
      title: Text(t('all_off_prot_t'), style: const TextStyle(fontSize: 18)),
      content: Text(t('all_off_prot_b', {'x': names}), style: TextStyle(color: C.textSoft, height: 1.5)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, 0), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
        TextButton(onPressed: () => Navigator.pop(ctx, 2), child: Text(t('all_off_all'), style: TextStyle(color: C.danger))),
        TextButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: Text(t('all_off_keep'), style: TextStyle(color: C.accent, fontWeight: FontWeight.w700))),
      ],
    ),
  );
  if (choice == 1) await state.offExceptProtected(s);
  if (choice == 2) await state.setOutlet(s.mac, 0, false);
}

class StripCard extends StatelessWidget {
  final AppState state;
  final Strip strip;
  final Widget? dragHandle;
  const StripCard({super.key, required this.state, required this.strip, this.dragHandle});

  @override
  Widget build(BuildContext context) {
    final s = strip;
    final stripTimers = state.timersFor(s.mac).where((x) => x.outlet == 0).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: cardBox(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          if (dragHandle != null) dragHandle!,
          Expanded(
            child: Row(children: [
              Flexible(
                child: Text(state.stripName(s),
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
              const SizedBox(width: 8),
              _badge(s.online),
            ]),
          ),
          const SizedBox(width: 8),
          Text('${s.livePower.toStringAsFixed(1)} W', textDirection: TextDirection.ltr, style: mono(14, color: C.accent)),
          IconButton(
            tooltip: t('strip_settings'),
            icon: Icon(Icons.tune, color: C.muted, size: 20),
            onPressed: () => openStripSheet(context, state, s.mac),
          ),
        ]),
        if (state.showMac)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(s.mac, textDirection: TextDirection.ltr, style: mono(11, color: C.faint, weight: FontWeight.w500)),
          ),
        if (stripTimers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(Icons.hourglass_bottom, size: 14, color: C.accent),
              const SizedBox(width: 4),
              Text(timerText(stripTimers.first), style: TextStyle(fontSize: 12, color: C.accent)),
            ]),
          ),
        const SizedBox(height: 6),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: s.outlets.map((o) => _OutletTile(state: state, strip: s, outlet: o)).toList(),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: FilledButton(
              onPressed: () => state.setOutlet(s.mac, 0, true),
              style: FilledButton.styleFrom(
                backgroundColor: C.accentBg,
                foregroundColor: C.accent,
                minimumSize: const Size(0, 44),
                side: BorderSide(color: C.tileOnBorder),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(t('all_on'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton(
              onPressed: () => guardedAllOff(context, state, s),
              style: OutlinedButton.styleFrom(
                foregroundColor: C.textSoft,
                minimumSize: const Size(0, 44),
                side: BorderSide(color: C.border),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(t('all_off'), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ]),
      ]),
    );
  }

  Widget _badge(bool online) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: online ? C.greenBg : C.surface2, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: online ? C.green : C.faint, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(online ? t('online') : t('offline'), style: TextStyle(fontSize: 11, color: online ? C.greenText : C.muted)),
        ]),
      );
}

String timerText(HubTimer x) {
  final when = x.inS <= 0 ? t('now') : t('after_x', {'x': _short(x.inS)});
  if (x.kind == 'cycle') return x.phase == 1 ? t('timer_on', {'x': when}) : t('timer_cycle', {'x': when});
  return x.kind == 'on' ? t('timer_on', {'x': when}) : t('timer_off', {'x': when});
}

String _short(int s) {
  if (s < 60) return '$s ${t('sec')}';
  if (s < 3600) return '${(s / 60).ceil()} ${t('min')}';
  return '${(s / 3600).toStringAsFixed(1)} ${t('hour')}';
}

class _OutletTile extends StatelessWidget {
  final AppState state;
  final Strip strip;
  final Outlet outlet;
  const _OutletTile({required this.state, required this.strip, required this.outlet});

  @override
  Widget build(BuildContext context) {
    final on = outlet.on;
    final pending = state.isPending(strip.mac, outlet.n);
    final name = state.outletName(strip, outlet.n);
    final tm = state.timersFor(strip.mac, outlet.n).where((x) => x.outlet == outlet.n).toList();
    return Material(
      color: on ? C.tileOn : C.tile,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: on ? C.tileOnBorder : C.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: pending ? null : () => guardedSwitch(context, state, strip, outlet, !on),
        onLongPress: () => openOutletSheet(context, state, strip.mac, outlet.n),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Icon(Icons.power_outlined, color: on ? C.accent : C.faint, size: 24),
                const SizedBox(width: 2),
                if (outlet.protected) Icon(Icons.shield_outlined, color: C.accent, size: 15, semanticLabel: t('protect')),
                if (outlet.locked) Icon(Icons.lock_outline, color: C.muted, size: 15, semanticLabel: t('child_lock')),
                if (tm.isNotEmpty || outlet.autoOffInS >= 0) Icon(Icons.hourglass_bottom, color: C.accent, size: 15),
                const Spacer(),
                if (pending)
                  SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent))
                else
                  SizedBox(
                    height: 28,
                    child: FittedBox(
                      child: Switch(
                        value: on,
                        onChanged: (v) => guardedSwitch(context, state, strip, outlet, v),
                        activeTrackColor: C.accent,
                        inactiveTrackColor: C.switchOff,
                        thumbColor: WidgetStateProperty.resolveWith((st) => st.contains(WidgetState.selected) ? C.onAccent : C.muted),
                        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
                      ),
                    ),
                  ),
              ]),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const SizedBox(height: 3),
                Row(children: [
                  Text(on ? '${outlet.powerW.toStringAsFixed(1)} W' : t('off'),
                      textDirection: TextDirection.ltr,
                      style: on ? mono(12, color: C.accent, weight: FontWeight.w500) : TextStyle(fontSize: 12, color: C.muted)),
                  const SizedBox(width: 8),
                  Text('${outlet.tempC}°C', textDirection: TextDirection.ltr, style: mono(12, color: _tempColor(outlet.tempC), weight: FontWeight.w500)),
                  if (tm.isNotEmpty || outlet.autoOffInS >= 0) ...[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        tm.isNotEmpty ? timerText(tm.first) : t('auto_off_left', {'x': _short(outlet.autoOffInS)}),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: C.accent),
                      ),
                    ),
                  ],
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Color _tempColor(int c) => c >= 60 ? C.danger : (c >= 45 ? C.accent : C.muted);
}
