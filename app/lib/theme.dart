import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens. Values switch with [C.use] before the app builds (dark / light).
class C {
  static bool dark = true;
  static Color bg = const Color(0xFF0D1117);
  static Color surface = const Color(0xFF151B23);
  static Color surface2 = const Color(0xFF1C2430);
  static Color tile = const Color(0xFF1A2029);
  static Color border = const Color(0xFF263040);
  static Color nav = const Color(0xFF10151C);
  static Color text = const Color(0xFFE8EDF3);
  static Color textSoft = const Color(0xFFC9D3DF);
  static Color muted = const Color(0xFF9AA7B8);
  static Color faint = const Color(0xFF5B6676);
  static Color accent = const Color(0xFFF2B544);
  static Color accentBg = const Color(0xFF2A2210);
  static Color tileOn = const Color(0xFF211C12);
  static Color tileOnBorder = const Color(0xFF6B5320);
  static Color onAccent = const Color(0xFF1A1300);
  static Color switchOff = const Color(0xFF333D4B);
  static Color miniOff = const Color(0xFF1F2733);
  static Color green = const Color(0xFF4CC38A);
  static Color greenBg = const Color(0xFF12261C);
  static Color greenText = const Color(0xFF7FD6A8);
  static Color blue = const Color(0xFF6CB6FF);
  static Color danger = const Color(0xFFE5766B);

  static void use(bool isDark) {
    dark = isDark;
    if (isDark) {
      bg = const Color(0xFF0D1117);
      surface = const Color(0xFF151B23);
      surface2 = const Color(0xFF1C2430);
      tile = const Color(0xFF1A2029);
      border = const Color(0xFF263040);
      nav = const Color(0xFF10151C);
      text = const Color(0xFFE8EDF3);
      textSoft = const Color(0xFFC9D3DF);
      muted = const Color(0xFF9AA7B8);
      faint = const Color(0xFF5B6676);
      accent = const Color(0xFFF2B544);
      accentBg = const Color(0xFF2A2210);
      tileOn = const Color(0xFF211C12);
      tileOnBorder = const Color(0xFF6B5320);
      onAccent = const Color(0xFF1A1300);
      switchOff = const Color(0xFF333D4B);
      miniOff = const Color(0xFF1F2733);
      green = const Color(0xFF4CC38A);
      greenBg = const Color(0xFF12261C);
      greenText = const Color(0xFF7FD6A8);
      blue = const Color(0xFF6CB6FF);
      danger = const Color(0xFFE5766B);
    } else {
      bg = const Color(0xFFF4F6F9);
      surface = const Color(0xFFFFFFFF);
      surface2 = const Color(0xFFEEF1F5);
      tile = const Color(0xFFF6F8FA);
      border = const Color(0xFFDDE3EA);
      nav = const Color(0xFFFFFFFF);
      text = const Color(0xFF111827);
      textSoft = const Color(0xFF334155);
      muted = const Color(0xFF5B6778);
      faint = const Color(0xFF94A0B0);
      accent = const Color(0xFFA86B00);
      accentBg = const Color(0xFFFBF0D9);
      tileOn = const Color(0xFFFFF7E6);
      tileOnBorder = const Color(0xFFE6C47A);
      onAccent = const Color(0xFFFFFFFF);
      switchOff = const Color(0xFFCBD3DD);
      miniOff = const Color(0xFFE6EAF0);
      green = const Color(0xFF1E8E5A);
      greenBg = const Color(0xFFE3F5EC);
      greenText = const Color(0xFF17774A);
      blue = const Color(0xFF2E6FD8);
      danger = const Color(0xFFC4453A);
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
