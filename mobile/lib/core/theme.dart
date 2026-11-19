import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ROUTESHIELD - PREMIUM CLEAR GLASS design tokens.
class RS {
  static const bg = Color(0xFFF3F6FA);
  static const navy = Color(0xFF16324F);
  static const text = Color(0xFF172B43);
  static const text2 = Color(0xFF526174);
  static const teal = Color(0xFF087F73);
  static const blue = Color(0xFF2463B9);
  static const amber = Color(0xFFFFF1D6);
  static const amberText = Color(0xFF7A4B00);
  static const red = Color(0xFFFDE8E7);
  static const redText = Color(0xFF9B1C1C);
  static const border = Color(0xFFD7E0E9);
  static const radius = 18.0;
  static const shadow = [BoxShadow(color: Color(0x14172B43), blurRadius: 18, offset: Offset(0, 6))];
  static const gradient = LinearGradient(colors: [Color(0xFF16324F), Color(0xFF1F5A7A), Color(0xFF087F73)], begin: Alignment.topLeft, end: Alignment.bottomRight);
}

ThemeData _build(ColorScheme cs, Color bg) {
  final base = ThemeData(useMaterial3: true, colorScheme: cs, brightness: cs.brightness);
  final tt = GoogleFonts.interTextTheme(base.textTheme).apply(bodyColor: cs.onSurface, displayColor: cs.onSurface);
  final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    scaffoldBackgroundColor: bg,
    textTheme: tt,
    appBarTheme: AppBarTheme(backgroundColor: bg, foregroundColor: cs.onSurface, elevation: 0, scrolledUnderElevation: 0, centerTitle: false,
        titleTextStyle: tt.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
    filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: shape, textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16))),
    outlinedButtonTheme: OutlinedButtonThemeData(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: shape, side: BorderSide(color: cs.outline))),
    inputDecorationTheme: InputDecorationTheme(
      filled: true, fillColor: cs.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outline)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.outline)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: cs.secondary, width: 2)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: cs.surface.withAlpha(215), indicatorColor: cs.secondary.withAlpha(40),
      labelTextStyle: WidgetStatePropertyAll(tt.labelMedium?.copyWith(fontWeight: FontWeight.w600)),
    ),
  );
}

ThemeData buildLightTheme() => _build(
    const ColorScheme(brightness: Brightness.light, primary: RS.navy, onPrimary: Colors.white, secondary: RS.teal, onSecondary: Colors.white,
        tertiary: RS.blue, error: RS.redText, onError: Colors.white, surface: Colors.white, onSurface: RS.text, onSurfaceVariant: RS.text2, outline: RS.border),
    RS.bg);

ThemeData buildDarkTheme() => _build(
    const ColorScheme(brightness: Brightness.dark, primary: Color(0xFF9CC3E8), onPrimary: Color(0xFF0B1B2B), secondary: Color(0xFF4FD1C5), onSecondary: Color(0xFF00201D),
        tertiary: Color(0xFF8AB4F8), error: Color(0xFFFFB4AB), onError: Color(0xFF3B0A06), surface: Color(0xFF16212F), onSurface: Color(0xFFE6EDF5),
        onSurfaceVariant: Color(0xFFB4C0CE), outline: Color(0xFF34455A)),
    const Color(0xFF0E1621));
