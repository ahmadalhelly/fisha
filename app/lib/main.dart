import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'i18n.dart';
import 'latin_digits.dart';
import 'screens/energy_screen.dart';
import 'screens/events_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/home_screen.dart';
import 'screens/schedules_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';
import 'services/notify_service.dart';
import 'widgets/common.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  NotifyService.initPort();
  runApp(MttlApp(state: AppState()));
}

class MttlApp extends StatefulWidget {
  final AppState state;
  const MttlApp({super.key, required this.state});

  @override
  State<MttlApp> createState() => _MttlAppState();
}

class _MttlAppState extends State<MttlApp> with WidgetsBindingObserver {
  late String _sig;
  bool _booted = false;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sig = _signature();
    s.addListener(_onState);
    _boot();
  }

  Future<void> _boot() async {
    await Future.wait([s.init(), Future.delayed(const Duration(milliseconds: 1100))]);
    if (mounted) setState(() => _booted = true);
    NotifyService.resume().catchError((_) {});
  }

  @override
  void dispose() {
    s.removeListener(_onState);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  String _signature() => '${s.themePref.index}-${s.langPref.index}-${s.accountType.isEmpty}';

  void _onState() {
    final sig = _signature();
    if (sig != _sig) setState(() => _sig = sig);
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  // 2.0.10: coming back to the app also checks that the notification service is running and hearing the hub
  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.resumed && _booted) NotifyService.resume().catchError((_) {});
  }

  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

  String _themeId() {
    switch (s.themePref) {
      case ThemePref.dark:
        return 'dark';
      case ThemePref.light:
        return 'light';
      case ThemePref.graphite:
        return 'graphite';
      case ThemePref.saffron:
        return 'saffron';
      case ThemePref.midnight:
        return 'midnight';
      case ThemePref.pearl:
        return 'pearl';
      case ThemePref.system:
        // the glass themes are the defaults: Midnight on a dark phone, Pearl on a light one
        return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark ? 'midnight' : 'pearl';
    }
  }

  String _lang() {
    switch (s.langPref) {
      case LangPref.ar:
        return 'ar';
      case LangPref.en:
        return 'en';
      case LangPref.system:
        return WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'en' ? 'en' : 'ar';
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeId = _booted ? _themeId() : 'midnight';
    final lang = _lang();
    C.useId(themeId);
    Tr.lang = lang;
    return MaterialApp(
      key: ValueKey('$themeId-$lang'),
      title: 'Fisha',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: Locale(lang),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        LatinArMaterialDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        child: !_booted
            ? const BootScreen(key: ValueKey('boot'))
            : s.accountType.isEmpty
                ? WelcomeScreen(key: const ValueKey('welcome'), state: s)
                : Shell(key: const ValueKey('shell'), state: s),
      ),
    );
  }
}

class BootScreen extends StatefulWidget {
  const BootScreen({super.key});

  @override
  State<BootScreen> createState() => _BootScreenState();
}

// 2.0.11 splash «د»: the plug settles in (0.92 → 1 with a fade), a soft mint glow opens right behind it, the bolt
// flickers once, then the name, the handle and a small dot that pulses twice. About 0.85 s; static when the system
// asks for reduced motion.
class _BootScreenState extends State<BootScreen> with SingleTickerProviderStateMixin {
  static const _mint = Color(0xFF2EE6B0);
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.of(context).disableAnimations) {
      _c.value = 1;
    } else {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// 0 → 1 between [from] and [to] ms of the timeline, with the splash curve
  double _seg(double ms, double from, double to, [Curve curve = const Cubic(.2, .8, .2, 1)]) =>
      curve.transform(((ms - from) / (to - from)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    const logo = 120.0;
    return Scaffold(
      backgroundColor: const Color(0xFF070D19),
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) {
            final ms = _c.value * 1500;
            final mark = _seg(ms, 0, 450);
            final glow = _seg(ms, 150, 950, Curves.easeOut);
            final f = ms >= 250 && ms <= 500 ? (ms - 250) / 250 : 0.0; // bolt flicker: up, dip, up, out
            final bolt = f == 0 ? 0.0 : (f < .3 ? f / .3 : f < .45 ? .35 : f < .65 ? 1.0 : (1 - f) / .35);
            final name = _seg(ms, 450, 750);
            final handle = _seg(ms, 550, 850);
            final p = ms < 850 ? 0.0 : ((ms - 850) / 300) % 1.0; // two pulses after the text is in
            final pulse = ms < 850 || ms >= 1450 ? 0.0 : math.sin(p * math.pi);
            return Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: logo * 2.2,
                height: logo * 1.5,
                child: Stack(alignment: Alignment.center, clipBehavior: Clip.none, children: [
                  Opacity(
                    opacity: glow * 0.9,
                    child: Container(
                      width: logo * 2.2,
                      height: logo * 2.2,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(colors: [_mint.withValues(alpha: 0.22), _mint.withValues(alpha: 0.06), _mint.withValues(alpha: 0)], stops: const [0, .45, 1]),
                      ),
                    ),
                  ),
                  Opacity(
                    opacity: mark,
                    child: Transform.scale(
                      scale: 0.92 + 0.08 * mark,
                      child: SizedBox(
                        width: logo,
                        height: logo,
                        child: Stack(children: [
                          const BrandMark(size: logo),
                          if (bolt > 0) Positioned.fill(child: CustomPaint(painter: _BoltPainter(bolt))),
                        ]),
                      ),
                    ),
                  ),
                ]),
              ),
              Opacity(
                opacity: name,
                child: Transform.translate(
                  offset: Offset(0, 6 * (1 - name)),
                  child: Text(t('app_name'), style: const TextStyle(color: _mint, fontSize: 30, fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(height: 6),
              Opacity(
                opacity: handle,
                child: Row(mainAxisSize: MainAxisSize.min, textDirection: TextDirection.ltr, children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: _mint,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: _mint.withValues(alpha: 0.6 * pulse), blurRadius: 4 + 6 * pulse, spreadRadius: 2 * pulse)],
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text('@ahmadalhelly', textDirection: TextDirection.ltr, style: TextStyle(color: Color(0xFF9AA7B8), fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]);
          },
        ),
      ),
    );
  }
}

/// Lights the bolt cut-out of the brand mark (same geometry as tool/brand.py, icon_fg.png at scale 0.95).
class _BoltPainter extends CustomPainter {
  final double v;
  const _BoltPainter(this.v);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 1024, sc = 0.95, cx = 512.0, y0 = 512 - 30 - 60 * sc;
    Offset pt(double dx, double dy) => Offset((cx + dx * sc) * k, (y0 + dy * sc) * k);
    final path = Path()
      ..moveTo(pt(18, 38).dx, pt(18, 38).dy)
      ..lineTo(pt(-52, 140).dx, pt(-52, 140).dy)
      ..lineTo(pt(-6, 140).dx, pt(-6, 140).dy)
      ..lineTo(pt(-24, 214).dx, pt(-24, 214).dy)
      ..lineTo(pt(54, 104).dx, pt(54, 104).dy)
      ..lineTo(pt(8, 104).dx, pt(8, 104).dy)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: 0.85 * v)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
    canvas.drawPath(path, Paint()..color = const Color(0xFFEFFFF9).withValues(alpha: v));
  }

  @override
  bool shouldRepaint(_BoltPainter old) => old.v != v;
}

class Shell extends StatefulWidget {
  final AppState state;
  const Shell({super.key, required this.state});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    state.addListener(_onState);
  }

  @override
  void dispose() {
    state.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    if (!mounted) return;
    final err = state.lastError;
    if (err != null) {
      state.clearError();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
    }
    final alert = state.takeAlert();
    if (alert != null && const {'temp', 'load', 'automation', 'missed', 'cycle', 'auto_off'}.contains(alert.type)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(eventText(state, alert))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final pages = [
          HomeScreen(state: state),
          SchedulesScreen(state: state),
          EnergyScreen(state: state),
          SettingsScreen(state: state),
        ];
        // the bar floats over the pages with rounded ends; each tab page pads its list and lifts its
        // add button by navInset/fabLift so nothing stays hidden under it
        // back on another tab goes to Home first; back on Home leaves the app
        return PopScope(
          canPop: state.tab == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) state.setTab(0);
          },
          child: Scaffold(
          extendBody: true,
          backgroundColor: C.bg,
          body: GlassWash(child: IndexedStack(index: state.tab, children: pages)),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: C.glass ? C.card : C.nav.withValues(alpha: C.dark ? 0.88 : 0.92),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: C.glass ? C.cardEdge : C.border.withValues(alpha: 0.8)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: C.dark ? 0.35 : 0.08),
                      blurRadius: 18,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: _NavGlass(
                child: NavigationBarTheme(
                  data: NavigationBarThemeData(
                    height: 60,
                    backgroundColor: Colors.transparent,
                    indicatorColor: C.accentBg,
                    labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                    labelTextStyle: WidgetStateProperty.resolveWith(
                      (st) => TextStyle(
                        fontSize: 11,
                        fontWeight: st.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w400,
                        color: st.contains(WidgetState.selected) ? C.accent : C.muted,
                      ),
                    ),
                    iconTheme: WidgetStateProperty.resolveWith(
                      (st) => IconThemeData(color: st.contains(WidgetState.selected) ? C.accent : C.muted),
                    ),
                  ),
                  child: NavigationBar(
                    height: 60,
                    elevation: 0,
                    backgroundColor: Colors.transparent,
                    selectedIndex: state.tab,
                    onDestinationSelected: state.setTab,
                    destinations: [
                      NavigationDestination(
                          icon: const Icon(Icons.home_outlined), selectedIcon: const Icon(Icons.home), label: t('nav_home')),
                      NavigationDestination(
                          icon: const Icon(Icons.schedule_outlined),
                          selectedIcon: const Icon(Icons.schedule),
                          label: t('nav_sched')),
                      NavigationDestination(
                          icon: const Icon(Icons.bar_chart_outlined),
                          selectedIcon: const Icon(Icons.bar_chart),
                          label: t('nav_energy')),
                      NavigationDestination(
                          icon: const Icon(Icons.settings_outlined),
                          selectedIcon: const Icon(Icons.settings),
                          label: t('nav_settings')),
                    ],
                  ),
                ),
                ),
              ),
            ),
          ),
        ),
        );
      },
    );
  }
}

/// Frosts whatever scrolls under the bottom bar on glass themes.
class _NavGlass extends StatelessWidget {
  final Widget child;
  const _NavGlass({required this.child});

  @override
  Widget build(BuildContext context) =>
      C.glass ? BackdropFilter(filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: child) : child;
}
