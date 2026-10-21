part of '../strip_card.dart';

/// Rated load: the MTTL-W01 is a 16 A strip (about 3500 W in total, and any single outlet may take the full load).
const double kStripMaxW = 3500;

const double kOutletMaxW = 3500;

/// Load bands of the rating: < 15 % green, 15–35 % yellow, 35–60 % orange, above 60 % red.
/// (A 1400 W hair dryer on a 3500 W strip is orange.)
const _orange = Color(0xFFFF8A3D);

int loadLevel(double watts, double maxW) {
  final r = watts / maxW;
  // same steps everywhere (outlet ring, strip card, all-outlets halo): orange from 70 %, red from 90 %
  return r >= 0.9 ? 3 : (r >= 0.7 ? 2 : 0);
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
    base = '${t('timer_loop', {'a': shortDuration(x.onS), 'b': shortDuration(x.offS)})} · ${x.phase == 1 ? t('loop_next_off', {'x': when}) : t('loop_next_on', {'x': when})}';
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
