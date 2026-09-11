import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/theme/app_theme.dart';
import 'package:flutter_ai_agent/core/theme/hermes_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

double _luminanceComponent(double value) {
  return value <= 0.04045
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
}

double _relativeLuminance(Color color) {
  final r = _luminanceComponent(color.r);
  final g = _luminanceComponent(color.g);
  final b = _luminanceComponent(color.b);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double _contrastRatio(Color color1, Color color2) {
  final l1 = _relativeLuminance(color1);
  final l2 = _relativeLuminance(color2);
  final lighter = math.max(l1, l2);
  final darker = math.min(l1, l2);
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  group('Hermes Nous Theme Tokens & Colors', () {
    test('HermesColors defines core deep obsidian and card surfaces', () {
      expect(HermesColors.deepObsidian, const Color(0xFF0A0D14));
      expect(HermesColors.cardSurface, const Color(0xFF131926));
      expect(HermesColors.border, const Color(0xFF1E293B));
    });

    test('HermesColors defines electric teal, emerald, and amber accents', () {
      expect(HermesColors.electricTeal, const Color(0xFF00F2FE));
      expect(HermesColors.accentTeal, const Color(0xFF008080));
      expect(HermesColors.emerald, const Color(0xFF10B981));
      expect(HermesColors.amber, const Color(0xFFF59E0B));
    });

    test('HermesColors maintains backward-compatible aliases and inks', () {
      expect(HermesColors.background, HermesColors.deepObsidian);
      expect(HermesColors.surface, HermesColors.cardSurface);
      expect(HermesColors.inkPrimary, isNotNull);
      expect(HermesColors.inkMuted, isNotNull);
      expect(HermesColors.hairline, isNotNull);
    });
  });

  group('HermesTypography Monospace & Styling', () {
    test('HermesTypography provides monospace styles for tools, json, and pills', () {
      final mono = HermesTypography.monospace();
      expect(mono.fontFamily, contains('JetBrainsMono'));

      final tool = HermesTypography.toolLabel();
      expect(tool.fontFamily, contains('JetBrainsMono'));
      expect(tool.fontWeight, FontWeight.w600);

      final jsonStyle = HermesTypography.jsonPayload();
      expect(jsonStyle.fontFamily, contains('JetBrainsMono'));

      final pill = HermesTypography.statusPill();
      expect(pill.fontFamily, contains('JetBrainsMono'));
      expect(pill.fontWeight, FontWeight.w600);

      final badge = HermesTypography.tierBadge();
      expect(badge.fontFamily, contains('JetBrainsMono'));
      expect(badge.fontWeight, FontWeight.w600);
    });
  });

  group('HermesTheme ThemeData & Contrast', () {
    test('HermesTheme.darkTheme applies deep obsidian background and card surfaces', () {
      final theme = HermesTheme.darkTheme;

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, HermesColors.deepObsidian);
      expect(theme.colorScheme.surface, HermesColors.cardSurface);
      expect(theme.colorScheme.primary, HermesColors.electricTeal);
      expect(theme.colorScheme.secondary, HermesColors.accentTeal);
      expect(theme.colorScheme.outline, HermesColors.border);
      expect(theme.cardTheme.color, HermesColors.cardSurface);
    });

    test('AppTheme.darkTheme uses Hermes Nous palette values', () {
      final theme = AppTheme.darkTheme;

      expect(theme.brightness, Brightness.dark);
      expect(theme.scaffoldBackgroundColor, HermesColors.deepObsidian);
      expect(theme.colorScheme.surface, HermesColors.cardSurface);
    });

    test('WCAG AA Color Contrast ratios exceed requirements', () {
      // Body text on deep obsidian (> 4.5:1)
      final primaryTextRatio = _contrastRatio(
        HermesColors.inkPrimary,
        HermesColors.deepObsidian,
      );
      expect(primaryTextRatio, greaterThan(7.0));

      // Electric Teal on deep obsidian (> 4.5:1)
      final electricTealRatio = _contrastRatio(
        HermesColors.electricTeal,
        HermesColors.deepObsidian,
      );
      expect(electricTealRatio, greaterThan(4.5));

      // Emerald indicator on card surface (> 3.0:1 for graphical UI elements)
      final emeraldRatio = _contrastRatio(
        HermesColors.emerald,
        HermesColors.cardSurface,
      );
      expect(emeraldRatio, greaterThan(3.0));

      // Amber tier badge on card surface (> 3.0:1 for graphical UI elements)
      final amberRatio = _contrastRatio(
        HermesColors.amber,
        HermesColors.cardSurface,
      );
      expect(amberRatio, greaterThan(3.0));
    });
  });
}
