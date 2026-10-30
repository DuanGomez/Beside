import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta "noche tierna": mapa oscuro y tranquilo con acentos rosados suaves.
class C {
  static const bg = Color(0xFF17131A);
  static const map = Color(0xFF111318);
  static const surface = Color(0xFF221C25);
  static const surface2 = Color(0xFF2A2230);
  static const border = Color(0xFF33293A);
  static const text = Color(0xFFF7EEF1);
  static const muted = Color(0xFFB9A9B0);
  static const accent = Color(0xFFF2789A);
  static const green = Color(0xFF5BD69A);
  static const amber = Color(0xFFF5B97A);
  static const danger = Color(0xFFFF6B7A);
  static const spotify = Color(0xFF1ED760);
  static const spotifyBg = Color(0xFF14201A);
  static const spotifyBorder = Color(0xFF1F3A2B);

  /// Colores para elegir en el perfil (cómo te ven en el mapa).
  static const people = [
    Color(0xFFF2789A),
    Color(0xFFA99BF5),
    Color(0xFF7FC8F2),
    Color(0xFFF5B97A),
    Color(0xFF5BD69A),
    Color(0xFFF2B33D),
  ];
}

Color hexColor(String? hex, [Color fallback = C.accent]) {
  if (hex == null || hex.length != 7) return fallback;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

String colorHex(Color c) =>
    '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

ThemeData buildTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: C.accent,
      onPrimary: C.bg,
      secondary: C.green,
      surface: C.surface,
      onSurface: C.text,
      error: C.danger,
    ),
  );
  final text = GoogleFonts.nunitoTextTheme(base.textTheme).apply(bodyColor: C.text, displayColor: C.text);
  return base.copyWith(
    textTheme: text,
    appBarTheme: AppBarTheme(
      backgroundColor: C.bg,
      foregroundColor: C.text,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: GoogleFonts.nunito(fontSize: 22, fontWeight: FontWeight.w900, color: C.text),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface,
      labelStyle: const TextStyle(color: C.muted),
      hintStyle: const TextStyle(color: C.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: C.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: C.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: C.accent, width: 1.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: C.bg,
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w900),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        minimumSize: const Size(0, 54),
        side: const BorderSide(color: C.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        textStyle: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w800),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: C.accent, textStyle: GoogleFonts.nunito(fontWeight: FontWeight.w800)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : C.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.green : C.border),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    sliderTheme: const SliderThemeData(activeTrackColor: C.accent, thumbColor: C.text, inactiveTrackColor: C.border),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: C.surface2,
      contentTextStyle: GoogleFonts.nunito(color: C.text, fontWeight: FontWeight.w700),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    dividerColor: C.border,
    dividerTheme: const DividerThemeData(color: C.border, thickness: 1),
  );
}
