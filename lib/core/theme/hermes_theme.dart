import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HermesColors {
  // Backgrounds
  static const Color stage = Color(0xFF0A0A20);
  static const Color surface = Color(0xFF18182D);
  static const Color panelHover = Color(0xFF2B2B3E);
  static const Color codeBg = Color(0xFF060612);

  // Brand
  static const Color primaryBlue = Color(0xFF0000F2);
  static const Color brandLift = Color(0xFF6E6EFF);
  static const Color neonAccent = Color(0xFFEDFF45);

  // Inks
  static const Color inkPrimary = Color(0xFFF5F5F5);
  static const Color inkBody = Color(0xCCF5F5F5);
  static const Color inkMuted = Color(0x99F5F5F5);
  static const Color hairline = Color(0x33F5F5F5);

  // Status
  static const Color success = Color(0xFF6EFFD6);
  static const Color warning = Color(0xFFFFCD42);
  static const Color danger = Color(0xFFFF8442);
  static const Color info = Color(0xFF6EDDFF);
}

class HermesTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: HermesColors.stage,
      colorScheme: const ColorScheme.dark(
        primary: HermesColors.primaryBlue,
        secondary: HermesColors.neonAccent,
        surface: HermesColors.surface,
        error: HermesColors.danger,
        onPrimary: HermesColors.inkPrimary,
        onSecondary: HermesColors.stage,
        onSurface: HermesColors.inkPrimary,
      ),
      cardTheme: CardThemeData(
        color: HermesColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6.0),
          side: const BorderSide(color: HermesColors.hairline, width: 0.8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HermesColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: GoogleFonts.ibmPlexSans(color: HermesColors.inkMuted, fontSize: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4.0),
          borderSide: const BorderSide(color: HermesColors.hairline, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4.0),
          borderSide: const BorderSide(color: HermesColors.brandLift, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: HermesColors.primaryBlue,
          foregroundColor: HermesColors.inkPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4.0)),
          textStyle: GoogleFonts.ibmPlexSans(fontSize: 14, fontWeight: FontWeight.w600),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      textTheme: TextTheme(
        displayLarge: GoogleFonts.oswald(fontSize: 48, fontWeight: FontWeight.bold, letterSpacing: -1.2, color: HermesColors.inkPrimary),
        displayMedium: GoogleFonts.oswald(fontSize: 36, fontWeight: FontWeight.w600, letterSpacing: -0.8, color: HermesColors.inkPrimary),
        displaySmall: GoogleFonts.oswald(fontSize: 28, fontWeight: FontWeight.w600, letterSpacing: -0.5, color: HermesColors.inkPrimary),
        titleLarge: GoogleFonts.oswald(fontSize: 24, fontWeight: FontWeight.w600, letterSpacing: -0.4, color: HermesColors.inkPrimary),
        titleMedium: GoogleFonts.ibmPlexSans(fontSize: 18, fontWeight: FontWeight.w600, color: HermesColors.inkPrimary),
        titleSmall: GoogleFonts.ibmPlexSans(fontSize: 15, fontWeight: FontWeight.w500, color: HermesColors.inkPrimary),
        bodyLarge: GoogleFonts.ibmPlexSans(fontSize: 16, fontWeight: FontWeight.normal, height: 1.5, color: HermesColors.inkBody),
        bodyMedium: GoogleFonts.ibmPlexSans(fontSize: 14, fontWeight: FontWeight.normal, height: 1.43, color: HermesColors.inkBody),
        bodySmall: GoogleFonts.ibmPlexSans(fontSize: 12, fontWeight: FontWeight.normal, height: 1.33, color: HermesColors.inkMuted),
        labelSmall: GoogleFonts.jetBrainsMono(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.8, color: HermesColors.inkMuted),
      ),
    );
  }
}
