import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../screens/outlet_sheet.dart';
import '../theme.dart';
import 'common.dart';
import 'wifi_arcs.dart';

/// Switch an outlet, asking first if it needs biometric or is protected and being turned off.
Future<void> guardedSwitch(BuildContext context, AppState state, Strip s, Outlet o, bool on) async {
  if (!s.online) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t('strip_offline_cmd'))));
    return;
  }
  if (!on && o.keepOn) {
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.surface,
        icon: Icon(Icons.push_pin_outlined, color: C.accent),
        title: Text(Tr.isAr ? 'المخرج محمي (مفتوح دائمًا)' : 'Outlet kept always on', style: const TextStyle(fontSize: 18)),
        content: Text(Tr.isAr ? 'هذا المخرج تم ضبطه ليعمل دائمًا ولا يمكن إيقافه إلا إذا قمت بإلغاء إعداد «إبقاء دائمًا شغال» أولاً.' : 'This outlet is set to keep always on. To turn it off, disable the Keep Always On setting first.', style: TextStyle(color: C.textSoft)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('cancel'), style: TextStyle(color: C.muted))),
        ],
      ),
    );
    return;
  }
  if (state.requiresBio(s.mac, o.n)) {
    final reason = Tr.isAr
        ? 'تأكيد البصمة للتحكم في «${state.outletName(s, o.n)}»'
        : 'Authenticate to switch "${state.outletName(s, o.n)}"';
    final ok = await authenticateBio(reason);
    if (!ok) return;
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

Future<void> guardedAllOn(BuildContext context, AppState state, Strip s) async {
  if (!s.online) return;
  final needsBio = s.outlets.any((o) => !o.on && state.requiresBio(s.mac, o.n));
  bool bioOk = true;
  if (needsBio) {
    final reason = Tr.isAr ? 'تأكيد البصمة لتشغيل الكل' : 'Authenticate for All On';
    bioOk = await authenticateBio(reason);
  }
  if (bioOk) {
    await state.setOutlet(s.mac, 0, true);
  } else {
    for (final o in s.outlets) {
      if (!o.on && !state.requiresBio(s.mac, o.n)) {
        await state.setOutlet(s.mac, o.n, true);
      }
    }
  }
}

Future<void> guardedAllOff(BuildContext context, AppState state, Strip s) async {
  if (!s.online) return;
  final bioOutlets = s.outlets.where((o) => o.on && state.requiresBio(s.mac, o.n)).toList();
  bool bioOk = true;
  if (bioOutlets.isNotEmpty) {
    final reason = Tr.isAr ? 'تأكيد البصمة لإيقاف الكل' : 'Authenticate for All Off';
    bioOk = await authenticateBio(reason);
  }
  final targets = s.outlets.where((o) => o.on && !o.keepOn && (bioOk || !state.requiresBio(s.mac, o.n))).toList();
  if (targets.isEmpty) return;

  final protectedOn = targets.where((o) => o.protected).toList();
  if (protectedOn.isEmpty) {
    if (bioOk && targets.length == s.onCount && s.outlets.every((o) => !o.keepOn)) {
      return state.setOutlet(s.mac, 0, false);
    } else {
      for (final o in targets) {
        await state.setOutlet(s.mac, o.n, false);
      }
      return;
    }
  }

  final names = protectedOn.map((o) => state.outletName(s, o.n)).join('، ');
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
  if (choice == 1) {
    for (final o in targets) {
      if (!o.protected) await state.setOutlet(s.mac, o.n, false);
    }
  } else if (choice == 2) {
    if (bioOk && targets.length == s.onCount && s.outlets.every((o) => !o.keepOn)) {
      await state.setOutlet(s.mac, 0, false);
    } else {
      for (final o in targets) {
        await state.setOutlet(s.mac, o.n, false);
      }
    }
  }
}


/// Rated load: the MTTL-W01 is a 16 A strip (about 3500 W in total, and any single outlet may take the full load).
const double kStripMaxW = 3500;
const double kOutletMaxW = 3500;

/// Load bands of the rating: < 15 % green, 15–35 % yellow, 35–60 % orange, above 60 % red.
/// (A 1400 W hair dryer on a 3500 W strip is orange.)
const _orange = Color(0xFFFF8A3D);
int loadLevel(double watts, double maxW) {
  final r = watts / maxW;
  return r >= 0.6 ? 3 : (r >= 0.35 ? 2 : (r >= 0.15 ? 1 : 0));
}

Color levelColor(int level) => switch (level) {
      3 => C.danger,
      2 => _orange,
      1 => C.warn,
      _ => C.green,
    };

Color loadColor(double watts, double maxW) => levelColor(loadLevel(watts, maxW));

/// Temperature bands: < 40 °C green, 40–50 yellow, 50–60 orange, 60+ red.
Color tempColor(int c) => c >= 60 ? C.danger : (c >= 50 ? _orange : (c >= 40 ? C.warn : C.green));

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
    if (o != null && o.keepOn) (Icons.push_pin_outlined, C.accent, Tr.isAr ? 'إبقاء دائمًا شغال' : 'Keep always on'),
    if (o != null && state.requiresBio(s.mac, o.n)) (Icons.fingerprint, C.accent, Tr.isAr ? 'يحتاج بصمة' : 'Biometric protected'),
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
                  Row(children: [
                    Flexible(
                      child: Text(state.stripName(s), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, height: 1.3)),
                    ),
                    const SizedBox(width: 6),
                    Builder(builder: (_) {
                      final tip = s.rssi != null ? '${s.rssi} dBm' : (online ? '—' : t('offline'));
                      return Tooltip(
                        message: tip,
                        child: WifiArcs(rssi: s.rssi),
                      );
                    }),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Flexible(
                      child: Text(
                        online ? '${t('n_of_4', {'a': s.onCount, 'b': s.outlets.length})} · ' : t('offline_kept'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: online ? C.muted : C.danger),
                      ),
                    ),
                    if (online)
                      Text('${s.maxTemp}°C', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11.5, color: tempColor(s.maxTemp), fontWeight: FontWeight.w600)),
                    if (online && s.voltage != null) ...[
                      const SizedBox(width: 8),
                      Container(width: 1, height: 10, color: C.border),
                      const SizedBox(width: 8),
                      Text('${s.voltage!.toStringAsFixed(0)} V', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11.5, color: voltColor(s.voltage!), fontWeight: FontWeight.w600)),
                    ],
                    if (stripBadges.isNotEmpty) ...[const SizedBox(width: 6), ...stripBadges],
                  ]),
                ]),
              ),
            ),
            Row(
              textDirection: TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                AnimatedNumber(value: online ? s.livePower : 0, style: mono(20, color: online ? loadColor(s.livePower, kStripMaxW) : C.faint)),
                const SizedBox(width: 3),
                Text('W', style: mono(12, color: C.muted, weight: FontWeight.w500)),
              ],
            ),
            IconButton(
              tooltip: t('strip_settings'),
              visualDensity: VisualDensity.compact,
              icon: Icon(Icons.tune, color: C.muted, size: 20),
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
                colors: C.dark ? [C.surface2, C.surface] : [C.surface, C.surface2],
              ),
              border: Border.all(color: C.border),
            ),
            child: Column(children: [
              Row(children: [
                for (final o in s.outlets) Expanded(child: _Socket(state: state, strip: s, outlet: o)),
              ]),
              const SizedBox(height: 12),
              _MasterSocket(state: state, strip: s),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _MasterSocket extends StatelessWidget {
  final AppState state;
  final Strip strip;
  const _MasterSocket({required this.state, required this.strip});

  @override
  Widget build(BuildContext context) {
    final s = strip;
    final online = s.online;
    final allOn = s.onCount == 4;
    final allOff = s.onCount == 0;
    final mixed = !allOn && !allOff;
    final on = online && (allOn || mixed);
    final pending = state.isPending(s.mac, 0);
    
    final load = on ? (s.livePower / kStripMaxW).clamp(0.0, 1.0) : 0.0;
    final String lbl = allOn ? t('all_on') : (allOff ? t('all_off') : t('n_of_4', {'a': s.onCount, 'b': 4}));

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: pending ? null : () {
        if (!online) return;
        if (allOn) guardedAllOff(context, state, s);
        else state.setOutlet(s.mac, 0, true);
      },
      onLongPress: () => openStripSheet(context, state, s.mac),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(children: [
          const SizedBox(height: 2),
          TweenAnimationBuilder<double>(
            tween: Tween(end: load),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => SizedBox(
              width: 62,
              height: 62,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(size: const Size(62, 62), painter: _SocketPainter(
                  on: on, load: v, level: loadLevel(s.livePower, kStripMaxW), hot: s.maxTemp >= 60, dark: C.dark,
                  isMaster: true, mixed: mixed,
                )),
                if (pending) SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(lbl, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? C.text : C.textSoft)),
          Text(
            on ? '${s.livePower.toStringAsFixed(s.livePower < 10 ? 1 : 0)} W' : (online ? t('off') : '—'),
            textDirection: TextDirection.ltr,
            style: on ? mono(11, color: loadColor(s.livePower, kStripMaxW), weight: FontWeight.w500) : TextStyle(fontSize: 11, color: C.faint),
          ),
          if (online) const SizedBox(height: 11),
        ]),
      ),
    );
  }
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
    final load = on ? (o.powerW / kOutletMaxW).clamp(0.0, 1.0) : 0.0;
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
                CustomPaint(size: const Size(62, 62), painter: _SocketPainter(on: on, load: v, level: loadLevel(o.powerW, kOutletMaxW), hot: o.tempC >= 60, dark: C.dark)),
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
            style: on ? mono(11, color: loadColor(o.powerW, kOutletMaxW), weight: FontWeight.w500) : TextStyle(fontSize: 11, color: C.faint),
          ),
          if (strip.online)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.thermostat, size: 11, color: tempColor(o.tempC)),
              Text('${o.tempC}°C', textDirection: TextDirection.ltr, style: mono(10.5, color: tempColor(o.tempC), weight: FontWeight.w500)),
            ]),
        ]),
      ),
    );
  }
}

/// Socket face (Schuko style) with a load ring.
class _SocketPainter extends CustomPainter {
  final bool on, hot, dark, isMaster, mixed;
  final double load;
  final int level;
  _SocketPainter({required this.on, required this.load, required this.level, required this.hot, required this.dark, this.isMaster = false, this.mixed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ringColor = hot ? C.danger : levelColor(level);
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
      final sweep = 2 * math.pi * math.max(0.12, load);
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
            colors: [Color.lerp(ringColor, C.surface, 0.35)!, ringColor],
            transform: const GradientRotation(-math.pi / 2),
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
    // face
    final face = r - 9;
    final bool innerOn = on && !mixed;
    canvas.drawCircle(
      c,
      face,
      Paint()
        ..shader = RadialGradient(
          colors: innerOn
              ? [ringColor.withValues(alpha: dark ? 0.35 : 0.25), dark ? C.tileOn : C.accentBg]
              : (dark ? [C.surface2, C.tile] : [C.surface, C.miniOff]),
        ).createShader(Rect.fromCircle(center: c, radius: face)),
    );
    canvas.drawCircle(c, face, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = innerOn ? ringColor.withValues(alpha: 0.6) : C.border);
    
    final holeColor = innerOn ? Color.lerp(ringColor, const Color(0xFF000000), 0.6)! : (dark ? C.bg : C.faint);
    
    if (isMaster) {
      final iconColor = mixed ? C.accent : holeColor;
      final iconStr = String.fromCharCode(Icons.power_settings_new.codePoint);
      final tp = TextPainter(
        text: TextSpan(text: iconStr, style: TextStyle(fontFamily: Icons.power_settings_new.fontFamily, fontSize: face * 0.9, color: iconColor)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    } else {
      // two pin holes
      final hole = Paint()..color = holeColor;
      canvas.drawCircle(c.translate(-face * 0.38, 0), face * 0.13, hole);
      canvas.drawCircle(c.translate(face * 0.38, 0), face * 0.13, hole);
      // earth clips
      final clip = Paint()
        ..color = innerOn ? ringColor.withValues(alpha: 0.8) : C.faint
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(c.translate(-face * 0.12, -face * 0.82), c.translate(face * 0.12, -face * 0.82), clip);
      canvas.drawLine(c.translate(-face * 0.12, face * 0.82), c.translate(face * 0.12, face * 0.82), clip);
    }
  }

  @override
  bool shouldRepaint(covariant _SocketPainter old) => true; // cheap, and picks up theme changes
}
