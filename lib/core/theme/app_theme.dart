import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const Color _darkSurface = Color(0xFF0F172A);
  static const Color _accentTeal = Color(0xFF008080);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _darkSurface,
      colorScheme: const ColorScheme.dark(
        surface: _darkSurface,
        primary: _accentTeal,
        secondary: _accentTeal,
        onSurface: Colors.white,
        onPrimary: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkSurface,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _accentTeal,
        foregroundColor: Colors.white,
      ),
      useMaterial3: true,
    );
  }
}
