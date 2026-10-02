import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens. Values switch with [C.use] before the app builds (dark / light).
class C {
  static bool dark = true;
  static Color bg = const Color(0xFF070D19);
  static Color surface = const Color(0xFF0E1628);
  static Color surface2 = const Color(0xFF16213A);
  static Color tile = const Color(0xFF111B2F);
  static Color border = const Color(0xFF1F2D48);
  static Color nav = const Color(0xFF0A1221);
  static Color text = const Color(0xFFE9F2FF);
  static Color textSoft = const Color(0xFFC2D1E8);
  static Color muted = const Color(0xFF8798B3);
  static Color faint = const Color(0xFF4D5C77);
  static Color accent = const Color(0xFF2EE6B0);
  static Color accentBg = const Color(0xFF0E2A2B);
  static Color tileOn = const Color(0xFF0D2524);
  static Color tileOnBorder = const Color(0xFF1E7D68);
  static Color onAccent = const Color(0xFF032019);
  static Color switchOff = const Color(0xFF2A3855);
  static Color miniOff = const Color(0xFF18233B);
  static Color green = const Color(0xFF3DDC97);
  static Color greenBg = const Color(0xFF0E2A20);
  static Color greenText = const Color(0xFF7BE6B7);
  static Color blue = const Color(0xFF38BDF8);
  static Color danger = const Color(0xFFFF6B6B);
  static Color accent2 = const Color(0xFF38BDF8);
  static Color warn = const Color(0xFFFFB547);

  static String themeId = 'dark';
  static void use(bool isDark) => useId(isDark ? 'dark' : 'light');

  /// dark / light / graphite (in between) / saffron (warm light with a saffron tint)
  static void useId(String id) {
    themeId = id;
    dark = id == 'dark' || id == 'graphite';
    switch (id) {
      case 'dark':
        bg = const Color(0xFF070D19);
        surface = const Color(0xFF0E1628);
        surface2 = const Color(0xFF16213A);
        tile = const Color(0xFF111B2F);
        border = const Color(0xFF1F2D48);
        nav = const Color(0xFF0A1221);
        text = const Color(0xFFE9F2FF);
        textSoft = const Color(0xFFC2D1E8);
        muted = const Color(0xFF8798B3);
        faint = const Color(0xFF4D5C77);
        accent = const Color(0xFF2EE6B0);
        accentBg = const Color(0xFF0E2A2B);
        tileOn = const Color(0xFF0D2524);
        tileOnBorder = const Color(0xFF1E7D68);
        onAccent = const Color(0xFF032019);
        switchOff = const Color(0xFF2A3855);
        miniOff = const Color(0xFF18233B);
        green = const Color(0xFF3DDC97);
        greenBg = const Color(0xFF0E2A20);
        greenText = const Color(0xFF7BE6B7);
        blue = const Color(0xFF38BDF8);
        danger = const Color(0xFFFF6B6B);
        accent2 = const Color(0xFF38BDF8);
        warn = const Color(0xFFFFB547);
        break;
      case 'light':
        bg = const Color(0xFFF1F6FA);
        surface = const Color(0xFFFFFFFF);
        surface2 = const Color(0xFFE8F0F6);
        tile = const Color(0xFFF5F9FC);
        border = const Color(0xFFD8E2ED);
        nav = const Color(0xFFFFFFFF);
        text = const Color(0xFF0B1424);
        textSoft = const Color(0xFF2B3A52);
        muted = const Color(0xFF5A6A82);
        faint = const Color(0xFF9AA8BC);
        accent = const Color(0xFF079E7D);
        accentBg = const Color(0xFFDFF6EF);
        tileOn = const Color(0xFFE9FAF4);
        tileOnBorder = const Color(0xFF8AD9C4);
        onAccent = const Color(0xFFFFFFFF);
        switchOff = const Color(0xFFC8D4E1);
        miniOff = const Color(0xFFE2E9F1);
        green = const Color(0xFF14935E);
        greenBg = const Color(0xFFE0F5EB);
        greenText = const Color(0xFF0F7A4D);
        blue = const Color(0xFF0284C7);
        danger = const Color(0xFFD94848);
        accent2 = const Color(0xFF0284C7);
        warn = const Color(0xFFC77700);
        break;
      case 'graphite':
        bg = const Color(0xFF1C1F24);
        surface = const Color(0xFF25292F);
        surface2 = const Color(0xFF30353C);
        tile = const Color(0xFF2A2E35);
        border = const Color(0xFF3B4149);
        nav = const Color(0xFF202328);
        text = const Color(0xFFEEF1F5);
        textSoft = const Color(0xFFC9CFD8);
        muted = const Color(0xFF98A1AD);
        faint = const Color(0xFF626A75);
        accent = const Color(0xFF4FD8B8);
        accentBg = const Color(0xFF1F3833);
        tileOn = const Color(0xFF233A35);
        tileOnBorder = const Color(0xFF3E8C79);
        onAccent = const Color(0xFF0B2A23);
        switchOff = const Color(0xFF474E58);
        miniOff = const Color(0xFF2C3138);
        green = const Color(0xFF5AD39A);
        greenBg = const Color(0xFF213A2E);
        greenText = const Color(0xFF8BE3B8);
        blue = const Color(0xFF7CC4F5);
        danger = const Color(0xFFFF7A7A);
        accent2 = const Color(0xFF7CC4F5);
        warn = const Color(0xFFF5B95A);
        break;
      case 'saffron':
        bg = const Color(0xFFF8F1E4);
        surface = const Color(0xFFFFFBF3);
        surface2 = const Color(0xFFF2E7D3);
        tile = const Color(0xFFFBF5EA);
        border = const Color(0xFFE8DAC0);
        nav = const Color(0xFFFFFBF3);
        text = const Color(0xFF2A2013);
        textSoft = const Color(0xFF4B3B25);
        muted = const Color(0xFF7E6B4F);
        faint = const Color(0xFFB7A588);
        accent = const Color(0xFFC27803);
        accentBg = const Color(0xFFF8E7C4);
        tileOn = const Color(0xFFFCF0D8);
        tileOnBorder = const Color(0xFFE5BF73);
        onAccent = const Color(0xFFFFFFFF);
        switchOff = const Color(0xFFDCCDB2);
        miniOff = const Color(0xFFEFE4CF);
        green = const Color(0xFF3C8D4E);
        greenBg = const Color(0xFFE6F2DF);
        greenText = const Color(0xFF2F7440);
        blue = const Color(0xFF2C7DA0);
        danger = const Color(0xFFC6402A);
        accent2 = const Color(0xFFB4532A);
        warn = const Color(0xFFB45309);
        break;
      default:
        useId('dark');
    }
  }
}

TextStyle mono(double size, {Color? color, FontWeight weight = FontWeight.w600}) =>
    GoogleFonts.ibmPlexMono(fontSize: size, color: color ?? C.text, fontWeight: weight, height: 1.1);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: C.dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: C.bg,
    colorScheme: C.dark
        ? ColorScheme.dark(
            primary: C.accent,
            onPrimary: C.onAccent,
            secondary: C.accent,
            surface: C.surface,
            onSurface: C.text,
            error: C.danger,
          )
        : ColorScheme.light(
            primary: C.accent,
            onPrimary: C.onAccent,
            secondary: C.accent,
            surface: C.surface,
            onSurface: C.text,
            error: C.danger,
          ),
  );
  final text = GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme).apply(bodyColor: C.text, displayColor: C.text);
  return base.copyWith(
    textTheme: text,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.dark ? C.surface2 : const Color(0xFF1F2733),
      contentTextStyle: TextStyle(color: C.dark ? C.text : Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      hintStyle: TextStyle(color: C.muted),
      labelStyle: TextStyle(color: C.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: C.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: C.accent),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(backgroundColor: C.surface),
    dividerColor: C.border,
  );
}

BoxDecoration cardBox({double radius = 22, Color? color, Color? border}) => BoxDecoration(
      color: color ?? C.surface,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border ?? C.border),
    );
