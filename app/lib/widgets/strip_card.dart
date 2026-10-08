import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../i18n.dart';
import '../models.dart';
import '../screens/outlet_sheet.dart';
import '../theme.dart';
import 'common.dart';
import 'notion_icon_picker.dart';
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
        content: Text(Tr.isAr ? 'هذا المخرج تم ضبطه ليعمل دائمًا ولا يمكن إيقافه إلا إذا قمت بإلغاء إعداد «التشغيل دائماً» أولاً.' : 'This outlet is set to keep always on. To turn it off, disable the Keep Always On setting first.', style: TextStyle(color: C.textSoft)),
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
    if (!ok || !context.mounted) return;
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
  if (state.requiresBio(s.mac, 0)) {
    if (!await authenticateBio(Tr.isAr ? 'تأكيد البصمة لتشغيل الكل' : 'Authenticate for All On')) return;
  }
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
  if (state.requiresBio(s.mac, 0)) {
    if (!await authenticateBio(Tr.isAr ? 'تأكيد البصمة لإيقاف الكل' : 'Authenticate for All Off')) return;
  }
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

  if (!context.mounted) return;
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
    if (o != null && o.keepOn) (Icons.push_pin_outlined, C.accent, t('keep_on')),
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
    final stripIcon = state.stripIcon(s.mac);
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 300),
      opacity: online ? 1 : 0.6,
      child: Container(
        decoration: BoxDecoration(
          color: C.card,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(
            color: online && s.onCount > 0 ? C.accent.withValues(alpha: C.dark ? 0.65 : 0.5) : C.cardEdge,
            width: online && s.onCount > 0 ? 1.5 : 1.0,
          ),
          boxShadow: online && s.onCount > 0
              ? [
                  BoxShadow(
                    color: C.accent.withValues(alpha: C.dark ? 0.28 : 0.2),
                    blurRadius: 22,
                    spreadRadius: 1,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            if (dragHandle != null) dragHandle!,
            PulseDot(color: online ? C.green : C.faint, active: online),
            const SizedBox(width: 6),
            Expanded(
              child: InkWell(
                onTap: () => openStripSheet(context, state, s.mac),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    if (stripIcon.isNotEmpty) ...[
                      FishaIcon(icon: stripIcon, size: 17),
                      const SizedBox(width: 6),
                    ],
                    Flexible(
                      child: Text(
                        state.stripName(s),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700, height: 1.25),
                      ),
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
                  const SizedBox(height: 5),
                  Row(children: [
                    Text(
                      online ? t('n_of_4', {'a': s.onCount, 'b': s.outlets.length}) : t('offline_kept'),
                      style: TextStyle(fontSize: 11.5, color: online ? C.textSoft : C.danger, fontWeight: FontWeight.w500),
                    ),
                    if (online) ...[
                      const SizedBox(width: 6),
                      Text('·', style: TextStyle(fontSize: 11, color: C.border)),
                      const SizedBox(width: 6),
                      Text('${s.maxTemp}°C', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11.5, color: tempColor(s.maxTemp), fontWeight: FontWeight.w600)),
                    ],
                    if (online && s.voltage != null) ...[
                      const SizedBox(width: 6),
                      Text('·', style: TextStyle(fontSize: 11, color: C.border)),
                      const SizedBox(width: 6),
                      Text('${s.voltage!.toStringAsFixed(0)} V', textDirection: TextDirection.ltr, style: TextStyle(fontSize: 11.5, color: voltColor(s.voltage!), fontWeight: FontWeight.w600)),
                    ],
                    if (stripBadges.isNotEmpty) ...[const SizedBox(width: 6), ...stripBadges],
                  ]),
                ]),
              ),
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  textDirection: TextDirection.ltr,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    AnimatedNumber(
                      value: online ? s.livePower : 0,
                      style: mono(18, color: online ? loadColor(s.livePower, kStripMaxW) : C.faint),
                    ),
                    const SizedBox(width: 2.5),
                    Text('W', style: mono(11, color: C.muted, weight: FontWeight.w500)),
                  ],
                ),
                if (online && s.voltage != null && s.voltage! > 0) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${(s.livePower / s.voltage!).toStringAsFixed(1)}A',
                    textDirection: TextDirection.ltr,
                    style: mono(11, color: C.textSoft, weight: FontWeight.w600),
                  ),
                ],
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
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: s.mac));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(Tr.isAr ? 'تم نسخ الماك آدرس: ${s.mac}' : 'MAC copied: ${s.mac}'),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(s.mac, textDirection: TextDirection.ltr, style: mono(10, color: C.faint, weight: FontWeight.w500)),
                      const SizedBox(width: 4),
                      Icon(Icons.copy, size: 10, color: C.faint),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          // the strip body
          Container(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: C.glass ? [C.well, C.well] : (C.dark ? [C.surface2, C.surface] : [C.surface, C.surface2]),
              ),
              border: Border.all(color: C.cardEdge),
            ),
            child: Column(children: [
              Row(children: [
                for (final o in s.outlets) Expanded(child: _Socket(state: state, strip: s, outlet: o)),
              ]),
              const SizedBox(height: 8),
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
    final String lbl = allOn ? t('master_all_on') : (allOff ? t('master_all_off') : t('master_n_of_4', {'a': s.onCount}));

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: pending ? null : () {
        if (!online) return;
        if (allOn) {
          guardedAllOff(context, state, s);
        } else {
          guardedAllOn(context, state, s);
        }
      },
      onLongPress: () => openStripSheet(context, state, s.mac),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        child: Column(children: [
          if (state.requiresBio(s.mac, 0))
            SizedBox(
              height: 14,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Tooltip(
                    message: Tr.isAr ? 'يحتاج بصمة' : 'Biometric protected',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1.5),
                      child: Icon(Icons.fingerprint, size: 12, color: C.accent),
                    ),
                  ),
                ]),
              ),
            ),
          const SizedBox(height: 2),
          TweenAnimationBuilder<double>(
            tween: Tween(end: load),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => SizedBox(
              width: 64,
              height: 64,
              child: Stack(alignment: Alignment.center, children: [
                _HaloSpin(
                  running: on,
                  builder: (spin) => CustomPaint(size: const Size(64, 64), painter: _SocketPainter(
                    on: on, load: v, level: loadLevel(s.livePower, kStripMaxW), hot: s.maxTemp >= 60, dark: C.dark,
                    isMaster: true, mixed: mixed, spin: spin,
                  )),
                ),
                if (pending) SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Text(lbl, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? C.text : C.textSoft)),
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
    final currentAmps = o.powerW / (strip.voltage ?? 220.0);
    final isAmpWarn = o.ampLimit > 0 && currentAmps >= (o.ampLimit * 0.85);
    final isTempWarn = o.tempC >= 55;
    final baseLevel = loadLevel(o.powerW, kOutletMaxW);
    final effLevel = (isAmpWarn || isTempWarn) ? math.max(baseLevel, 2) : baseLevel;
    final effHot = o.tempC >= 60 || (o.ampLimit > 0 && currentAmps >= o.ampLimit);

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
              width: 64,
              height: 64,
              child: Stack(alignment: Alignment.center, children: [
                CustomPaint(size: const Size(64, 64), painter: _SocketPainter(on: on, load: v, level: effLevel, hot: effHot, dark: C.dark)),
                if (pending) SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2, color: C.accent)),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            if (state.outletIcon(strip.mac, o.n).isNotEmpty) ...[
              FishaIcon(icon: state.outletIcon(strip.mac, o.n), size: 12, color: on ? C.text : C.textSoft),
              const SizedBox(width: 3),
            ],
            Flexible(
              child: Text(state.outletName(strip, o.n),
                  maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? C.text : C.textSoft)),
            ),
          ]),
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
  final double spin; // 0..1, the travelling highlight on the master's load halo
  _SocketPainter({required this.on, required this.load, required this.level, required this.hot, required this.dark, this.isMaster = false, this.mixed = false, this.spin = 0});

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
    if (isMaster && on) {
      // load halo: the ring measures the strip's real draw against its 3500 W limit,
      // orange from 70 %, red from 90 % (or when it runs hot)
      final haloColor = hot || load >= 0.9 ? C.danger : (load >= 0.7 ? const Color(0xFFFF9F43) : C.accent);
      canvas.drawCircle(c, r - 6, Paint()
        ..color = haloColor.withValues(alpha: 0.08 + 0.22 * load)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
      final sweep = 2 * math.pi * math.max(0.04, load);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r - 3), -math.pi / 2, sweep, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = haloColor);
      final a = -math.pi / 2 + 2 * math.pi * spin;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * (r - 3), 1.6, Paint()..color = Colors.white.withValues(alpha: 0.75));
    }
    if (on && !isMaster) {
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
    
    // sunken look: the face darkens toward its rim, like a socket set into the strip
    canvas.drawCircle(
      c,
      face,
      Paint()
        ..shader = RadialGradient(
          stops: const [0.68, 1.0],
          colors: [const Color(0x00000000), Color.fromRGBO(0, 0, 0, dark ? 0.38 : 0.16)],
        ).createShader(Rect.fromCircle(center: c, radius: face)),
    );
    final holeColor = innerOn ? Color.lerp(ringColor, const Color(0xFF000000), 0.6)! : (dark ? const Color(0xFF05080E) : C.faint);
    
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
      // pins and earth clips sit at 45°, like the sockets on the real MTTL-W01
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(math.pi / 4);
      canvas.translate(-c.dx, -c.dy);
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
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SocketPainter old) => true; // cheap, and picks up theme changes
}

/// Drives the slow travelling highlight on the master's load halo while anything is on.
class _HaloSpin extends StatefulWidget {
  final bool running;
  final Widget Function(double spin) builder;
  const _HaloSpin({required this.running, required this.builder});

  @override
  State<_HaloSpin> createState() => _HaloSpinState();
}

class _HaloSpinState extends State<_HaloSpin> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    if (widget.running) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant _HaloSpin old) {
    super.didUpdateWidget(old);
    if (widget.running && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.running && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _c, builder: (_, __) => widget.builder(_c.value));
}
