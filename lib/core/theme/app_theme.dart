import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/theme/hermes_theme.dart';

class AppTheme {
  AppTheme._();

  static const Color darkSurface = HermesColors.deepObsidian;
  static const Color cardSurface = HermesColors.cardSurface;
  static const Color border = HermesColors.border;
  static const Color accentTeal = HermesColors.accentTeal;
  static const Color electricTeal = HermesColors.electricTeal;

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: HermesColors.deepObsidian,
      colorScheme: const ColorScheme.dark(
        surface: HermesColors.cardSurface,
        primary: HermesColors.electricTeal,
        secondary: HermesColors.accentTeal,
        outline: HermesColors.border,
        outlineVariant: HermesColors.border,
        onSurface: HermesColors.inkPrimary,
        onPrimary: HermesColors.deepObsidian,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: HermesColors.deepObsidian,
        foregroundColor: HermesColors.inkPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: HermesColors.accentTeal,
        foregroundColor: Colors.white,
      ),
      cardTheme: CardThemeData(
        color: HermesColors.cardSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8.0),
          side: const BorderSide(color: HermesColors.border, width: 0.8),
        ),
      ),
      useMaterial3: true,
    );
  }
}
