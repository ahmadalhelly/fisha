import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'i18n.dart';
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
      case ThemePref.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark ? 'dark' : 'light';
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
    final themeId = _booted ? _themeId() : 'dark';
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

class _BootScreenState extends State<BootScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF070D19),
      body: Center(
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, child) {
            final v = Curves.easeOutBack.transform(_c.value.clamp(0.0, 1.0));
            return Opacity(opacity: _c.value, child: Transform.scale(scale: 0.7 + 0.3 * v, child: child));
          },
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const BrandMark(size: 120),
            const SizedBox(height: 8),
            Text(t('app_name'), style: const TextStyle(color: Color(0xFF2EE6B0), fontSize: 30, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            const Text('@ahmadalhelly', textDirection: TextDirection.ltr, style: TextStyle(color: Color(0xFF9AA7B8), fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ),
    );
  }
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
        return Scaffold(
          extendBody: true,
          backgroundColor: C.bg,
          body: IndexedStack(index: state.tab, children: pages),
          bottomNavigationBar: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: C.nav.withValues(alpha: C.dark ? 0.88 : 0.92),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: C.border.withValues(alpha: 0.8)),
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
        );
      },
    );
  }
}
