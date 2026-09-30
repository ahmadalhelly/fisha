import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens (from the "MTTL Hub App — Screens" canvas).
class C {
  static const bg = Color(0xFF0D1117);
  static const surface = Color(0xFF151B23);
  static const surface2 = Color(0xFF1C2430);
  static const tile = Color(0xFF1A2029);
  static const border = Color(0xFF263040);
  static const nav = Color(0xFF10151C);
  static const text = Color(0xFFE8EDF3);
  static const textSoft = Color(0xFFC9D3DF);
  static const muted = Color(0xFF9AA7B8);
  static const faint = Color(0xFF5B6676);
  static const accent = Color(0xFFF2B544);
  static const accentBg = Color(0xFF2A2210);
  static const tileOn = Color(0xFF211C12);
  static const tileOnBorder = Color(0xFF6B5320);
  static const onAccent = Color(0xFF1A1300);
  static const switchOff = Color(0xFF333D4B);
  static const green = Color(0xFF4CC38A);
  static const greenBg = Color(0xFF12261C);
  static const greenText = Color(0xFF7FD6A8);
  static const blue = Color(0xFF6CB6FF);
  static const danger = Color(0xFFE5766B);
}

TextStyle mono(double size, {Color color = C.text, FontWeight weight = FontWeight.w600}) =>
    GoogleFonts.ibmPlexMono(fontSize: size, color: color, fontWeight: weight, height: 1.1);

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
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
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: C.surface2,
      contentTextStyle: TextStyle(color: C.text),
      behavior: SnackBarBehavior.floating,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      hintStyle: const TextStyle(color: C.muted),
      labelStyle: const TextStyle(color: C.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: C.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: C.accent),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: C.surface),
  );
}

BoxDecoration cardBox({double radius = 22, Color color = C.surface, Color border = C.border}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border),
    );
