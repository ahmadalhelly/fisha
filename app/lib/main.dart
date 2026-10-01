import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_state.dart';
import 'i18n.dart';
import 'screens/home_screen.dart';
import 'screens/placeholder_screen.dart';
import 'screens/settings_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.init();
  runApp(MttlApp(state: state));
}

class MttlApp extends StatefulWidget {
  final AppState state;
  const MttlApp({super.key, required this.state});

  @override
  State<MttlApp> createState() => _MttlAppState();
}

class _MttlAppState extends State<MttlApp> with WidgetsBindingObserver {
  late String _sig;

  AppState get s => widget.state;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sig = _signature();
    s.addListener(_onState);
  }

  @override
  void dispose() {
    s.removeListener(_onState);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Rebuild the whole app only when the theme or language actually changes.
  String _signature() => '${s.themePref.index}-${s.langPref.index}';

  void _onState() {
    final sig = _signature();
    if (sig != _sig) setState(() => _sig = sig);
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

  bool _isDark() {
    switch (s.themePref) {
      case ThemePref.dark:
        return true;
      case ThemePref.light:
        return false;
      case ThemePref.system:
        return WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    }
  }

  String _lang() {
    switch (s.langPref) {
      case LangPref.ar:
        return 'ar';
      case LangPref.en:
        return 'en';
      case LangPref.system:
        final l = WidgetsBinding.instance.platformDispatcher.locale.languageCode;
        return l == 'en' ? 'en' : (l == 'ar' ? 'ar' : 'ar');
    }
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark();
    final lang = _lang();
    C.use(dark);
    Tr.lang = lang;
    return MaterialApp(
      key: ValueKey('$dark-$lang'),
      title: 'MTTL Hub',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      locale: Locale(lang),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Shell(state: s),
    );
  }
}

class Shell extends StatelessWidget {
  final AppState state;
  const Shell({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final pages = [
          HomeScreen(state: state, onOpenSettings: () => state.setTab(3)),
          PlaceholderScreen(title: t('nav_sched'), note: t('ph_sched')),
          PlaceholderScreen(title: t('nav_energy'), note: t('ph_energy')),
          SettingsScreen(state: state),
        ];
        return Scaffold(
          body: IndexedStack(index: state.tab, children: pages),
          bottomNavigationBar: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: C.nav,
              indicatorColor: C.accentBg,
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
        );
      },
    );
  }
}
