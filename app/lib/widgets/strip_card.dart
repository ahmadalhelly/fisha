import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../screens/outlet_sheet.dart';
import '../theme.dart';
import 'common.dart';

/// Switch an outlet, asking first if it is protected and being turned off.
Future<void> guardedSwitch(BuildContext context, AppState state, Strip s, Outlet o, bool on) async {
  if (!s.online) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('strip_offline_cmd'))));
    return;
  }
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
  if (!s.online) return;
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

/// "1:40 h", "25 min", "40 s"
String shortDuration(int s) {
  if (s < 60) return '$s ${t('sec')}';
  if (s < 3600) return '${(s / 60).ceil()} ${t('min')}';
  final h = s ~/ 3600, m = (s % 3600) ~/ 60;
  return m == 0 ? '$h ${t('hour')}' : '$h:${two(m)} ${t('hour')}';
}

String timerText(HubTimer x) {
  final when = x.inS <= 0 ? t('now') : t('after_x', {'x': shortDuration(x.inS)});
  final String base;
  if (x.kind == 'loop') {
    base = t('timer_loop', {'a': shortDuration(x.onS), 'b': shortDuration(x.offS)}) + ' · ' + (x.phase == 1 ? t('loop_next_off', {'x': when}) : t('loop_next_on', {'x': when}));
    return base;
  }
  if (x.kind == 'cycle') {
    base = x.phase == 1 ? t('timer_on', {'x': when}) : t('timer_cycle', {'x': when});
  } else {
    base = x.kind == 'on' ? t('timer_on', {'x': when}) : t('timer_off', {'x': when});
  }
  return x.repeatS > 0 ? '$base · ${t('repeat_every', {'x': shortDuration(x.repeatS)})}' : base;
}

IconData timerIcon(HubTimer x) => x.kind == 'loop' ? Icons.all_inclusive : (x.kind == 'cycle' ? Icons.restart_alt : Icons.hourglass_bottom);

/// Small icons for everything that is set on an outlet (or on the whole strip when [o] is null).
List<Widget> badgesFor(AppState state, Strip s, Outlet? o, {double size = 13}) {
  final n = o?.n ?? 0;
  final timers = state.timersFor(s.mac).where((x) => x.outlet == n).toList();
  final icons = <(IconData, Color, String)>[
    if (o == null ? s.hasSchedule : o.hasSchedule) (Icons.schedule, C.accent2, t('badge_sched')),
    if (o == null ? s.hasRule : o.hasRule) (Icons.bolt, C.warn, t('badge_rule')),
    for (final x in timers) (timerIcon(x), C.accent, timerText(x)),
    if (o != null && o.autoOffMin > 0) (Icons.timer_outlined, C.accent, t('auto_off')),
    if (o != null && o.protected) (Icons.shield, C.accent, t('protect')),
    if (o != null && o.locked) (Icons.lock, C.muted, t('child_lock')),
  ];
  return [
    for (final (icon, color, tip) in icons)
      Tooltip(message: tip, child: Padding(padding: const EdgeInsets.symmetric(horizontal: 1.5), child: Icon(icon, size: size, color: color))),
  ];
}

/// A strip drawn as the real thing: one body with four sockets that light up and show their load as a ring.
class StripCard extends StatelessWidget {
  final AppState state;
  final Strip strip;
  final Widget? dragHandle;
  const StripCard({super.key, required this.state, required this.strip, this.dragHandle});

  @override
  Widget build(BuildContext context) {
    final s = strip;
    final online = s.online;
    final stripBadges = badgesFor(state, s, null);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: online ? 1 : 0.6,
      child: Container(
        decoration: BoxDecoration(
          color: C.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: online && s.onCount > 0 ? C.tileOnBorder.withValues(alpha: 0.6) : C.border),
          boxShadow: online && s.onCount > 0
              ? [BoxShadow(color: C.accent.withValues(alpha: C.dark ? 0.08 : 0.12), blurRadius: 24, offset: const Offset(0, 8))]
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            if (dragHandle != null) dragHandle!,
            PulseDot(color: online ? C.green : C.faint, active: online),
            const SizedBox(width: 4),
            Expanded(
              child: InkWell(
                onTap: () => openStripSheet(context, state, s.mac),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(state.stripName(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  Row(children: [
                    Flexible(
                      child: Text(
                        online ? '${t('n_of_4', {'a': s.onCount, 'b': s.outlets.length})} · ${s.maxTemp}°C' : t('offline_kept'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: online ? C.muted : C.danger),
                      ),
                    ),
                    if (stripBadges.isNotEmpty) ...[const SizedBox(width: 6), ...stripBadges],
                  ]),
                ]),
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              AnimatedNumber(value: online ? s.livePower : 0, style: mono(20, color: online ? C.accent : C.faint)),
              Text('W', style: mono(10, color: C.muted, weight: FontWeight.w500)),
            ]),
            IconButton(
              tooltip: t('strip_settings'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.more_vert, color: C.muted, size: 20),
              onPressed: () => openStripSheet(context, state, s.mac),
            ),
          ]),
          if (state.showMac)
            Text(s.mac, textDirection: TextDirection.ltr, style: mono(10, color: C.faint, weight: FontWeight.w500)),
          const SizedBox(height: 12),
          // the strip body
          Container(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: C.dark ? [const Color(0xFF15203A), const Color(0xFF0C1427)] : [const Color(0xFFFFFFFF), const Color(0xFFEAF1F7)],
              ),
              border: Border.all(color: C.border),
            ),
            child: Row(children: [
              for (final o in s.outlets) Expanded(child: _Socket(state: state, strip: s, outlet: o)),
            ]),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _pill(context, Icons.power_settings_new, t('all_on'), online ? () => state.setOutlet(s.mac, 0, true) : null, filled: true)),
            const SizedBox(width: 8),
            Expanded(child: _pill(context, Icons.power_off_outlined, t('all_off'), online ? () => guardedAllOff(context, state, s) : null)),
          ]),
        ]),
      ),
    );
  }

  Widget _pill(BuildContext context, IconData icon, String label, VoidCallback? onTap, {bool filled = false}) => Material(
        color: filled ? C.accentBg : Colors.transparent,
        shape: StadiumBorder(side: BorderSide(color: filled ? C.tileOnBorder : C.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: SizedBox(
            height: 40,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 17, color: onTap == null ? C.faint : (filled ? C.accent : C.textSoft)),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: onTap == null ? C.faint : (filled ? C.accent : C.textSoft))),
            ]),
          ),
        ),
      );
}

class _Socket extends StatelessWidget {
  final AppState state;
  final Strip strip;
  final Outlet outlet;
  const _Socket({required this.state, required this.strip, required this.outlet});

  @override
  Widget build(BuildContext context) {
    final o = outlet;
    final on = strip.online && o.on;
    final pending = state.isPending(strip.mac, o.n);
    final badges = badgesFor(state, strip, o, size: 12);
    final load = on ? (o.powerW / 2000).clamp(0.0, 1.0) : 0.0;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: pending ? null : () => guardedSwitch(context, state, strip, o, !o.on),
      onLongPress: () => openOutletSheet(context, state, strip.mac, o.n),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(children: [
          SizedBox(
            height: 14,
            child: FittedBox(fit: BoxFit.scaleDown, child: Row(mainAxisSize: MainAxisSize.min, children: badges)),
          ),
          const SizedBox(height: 4),
          TweenAnimationBuilder<double>(
            tween: Tween(end: load),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => SizedBox(
              width: 62,
              height: 62,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(size: const Size(62, 62), painter: _SocketPainter(on: on, load: v, hot: o.tempC >= 60, dark: C.dark)),
                if (pending) SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(state.outletName(strip, o.n),
              maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? C.text : C.textSoft)),
          Text(
            on ? '${o.powerW.toStringAsFixed(o.powerW < 10 ? 1 : 0)} W' : (strip.online ? t('off') : '—'),
            textDirection: TextDirection.ltr,
            style: on ? mono(11, color: C.accent, weight: FontWeight.w500) : TextStyle(fontSize: 11, color: C.faint),
          ),
        ]),
      ),
    );
  }
}

/// Socket face (Schuko style) with a load ring.
class _SocketPainter extends CustomPainter {
  final bool on, hot, dark;
  final double load;
  _SocketPainter({required this.on, required this.load, required this.hot, required this.dark});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ringColor = hot ? C.danger : C.accent;
    // track
    canvas.drawCircle(c, r - 3, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = C.border);
    if (on) {
      // glow
      canvas.drawCircle(c, r - 6, Paint()
        ..color = ringColor.withValues(alpha: 0.22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      // load arc
      final sweep = 2 * math.pi * math.max(0.06, load);
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r - 3),
        -math.pi / 2,
        sweep,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            startAngle: -math.pi / 2,
            endAngle: -math.pi / 2 + sweep,
            colors: hot ? [C.warn, C.danger] : [C.accent, C.accent2],
            transform: const GradientRotation(-math.pi / 2),
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
    // face
    final face = r - 9;
    canvas.drawCircle(
      c,
      face,
      Paint()
        ..shader = RadialGradient(
          colors: on
              ? [ringColor.withValues(alpha: dark ? 0.35 : 0.25), dark ? const Color(0xFF0F2A2C) : const Color(0xFFDDF6EE)]
              : (dark ? [const Color(0xFF1E2A44), const Color(0xFF131C30)] : [const Color(0xFFFFFFFF), const Color(0xFFE3EAF2)]),
        ).createShader(Rect.fromCircle(center: c, radius: face)),
    );
    canvas.drawCircle(c, face, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = on ? ringColor.withValues(alpha: 0.6) : C.border);
    // two pin holes
    final hole = Paint()..color = on ? (dark ? const Color(0xFF062019) : const Color(0xFF0B5E4B)) : (dark ? const Color(0xFF0A1020) : const Color(0xFFB9C6D4));
    canvas.drawCircle(c.translate(-face * 0.38, 0), face * 0.13, hole);
    canvas.drawCircle(c.translate(face * 0.38, 0), face * 0.13, hole);
    // earth clips
    final clip = Paint()
      ..color = on ? ringColor.withValues(alpha: 0.8) : C.faint
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c.translate(-face * 0.12, -face * 0.82), c.translate(face * 0.12, -face * 0.82), clip);
    canvas.drawLine(c.translate(-face * 0.12, face * 0.82), c.translate(face * 0.12, face * 0.82), clip);
  }

  @override
  bool shouldRepaint(covariant _SocketPainter old) => old.on != on || old.load != load || old.hot != hot || old.dark != dark;
}
