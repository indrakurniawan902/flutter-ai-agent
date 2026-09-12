import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Hermes / Nous Research aesthetic color tokens.
class HermesColors {
  // Core Hermes Nous Tokens
  static const Color deepObsidian = Color(0xFF0A0D14);
  static const Color cardSurface = Color(0xFF131926);
  static const Color border = Color(0xFF1E293B);

  // Accents & Status Indicators
  static const Color electricTeal = Color(0xFF00F2FE);
  static const Color accentTeal = Color(0xFF008080);
  static const Color emerald = Color(0xFF10B981);
  static const Color amber = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFFF8442);
  static const Color rose = Color(0xFFEF4444);

  // Inks & Foregrounds
  static const Color inkPrimary = Color(0xFFF8FAFC);
  static const Color inkSecondary = Color(0xFF94A3B8);
  static const Color inkBody = Color(0xCCF8FAFC);
  static const Color inkMuted = Color(0xFF64748B);
  static const Color hairline = Color(0x33F8FAFC);

  // Backward-compatible aliases
  static const Color stage = deepObsidian;
  static const Color background = deepObsidian;
  static const Color surface = cardSurface;
  static const Color surfaceBorder = border;
  static const Color panelHover = Color(0xFF1E293B);
  static const Color codeBg = Color(0xFF060612);

  static const Color primaryBlue = Color(0xFF0000F2);
  static const Color brandLift = Color(0xFF6E6EFF);
  static const Color neonAccent = Color(0xFFEDFF45);

  static const Color success = emerald;
  static const Color warning = amber;
  static const Color info = electricTeal;
}

/// Monospace typography helper for technical agent tools, payloads, and status chips.
class HermesTypography {
  HermesTypography._();

  static TextStyle monospace({
    Color? color,
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.normal,
    double? height,
    double? letterSpacing,
  }) {
    return GoogleFonts.jetBrainsMono(
      color: color ?? HermesColors.inkPrimary,
      fontSize: fontSize,
      fontWeight: fontWeight,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle toolLabel({
    Color? color,
    double fontSize = 12,
    FontWeight fontWeight = FontWeight.w600,
  }) {
    return GoogleFonts.jetBrainsMono(
      color: color ?? HermesColors.electricTeal,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: 0.2,
    );
  }

  static TextStyle jsonPayload({
    Color? color,
    double fontSize = 12,
    double? height = 1.4,
  }) {
    return GoogleFonts.jetBrainsMono(
      color: color ?? HermesColors.inkSecondary,
      fontSize: fontSize,
      height: height,
    );
  }

  static TextStyle statusPill({
    Color? color,
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w600,
    double? letterSpacing = 0.5,
  }) {
    return GoogleFonts.jetBrainsMono(
      color: color ?? HermesColors.emerald,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle tierBadge({
    Color? color,
    double fontSize = 11,
    FontWeight fontWeight = FontWeight.w600,
    double? letterSpacing = 0.5,
  }) {
    return GoogleFonts.jetBrainsMono(
      color: color ?? HermesColors.amber,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }
}

class HermesTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: HermesColors.deepObsidian,
      colorScheme: const ColorScheme.dark(
        primary: HermesColors.electricTeal,
        secondary: HermesColors.accentTeal,
        surface: HermesColors.cardSurface,
        error: HermesColors.danger,
        outline: HermesColors.border,
        outlineVariant: HermesColors.border,
        onPrimary: HermesColors.deepObsidian,
        onSecondary: HermesColors.inkPrimary,
        onSurface: HermesColors.inkPrimary,
        onSurfaceVariant: HermesColors.inkSecondary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: HermesColors.deepObsidian,
        foregroundColor: HermesColors.inkPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      cardTheme: CardThemeData(
        color: HermesColors.cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6.0),
          side: const BorderSide(color: HermesColors.border, width: 0.8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: HermesColors.cardSurface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        hintStyle: GoogleFonts.ibmPlexSans(color: HermesColors.inkMuted, fontSize: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4.0),
          borderSide: const BorderSide(color: HermesColors.border, width: 0.8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4.0),
          borderSide: const BorderSide(color: HermesColors.electricTeal, width: 1.2),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: HermesColors.accentTeal,
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
