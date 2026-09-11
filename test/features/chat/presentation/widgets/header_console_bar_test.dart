import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/header_console_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createTestApp(Widget child, {Size size = const Size(400, 800)}) {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Scaffold(
          body: Center(child: child),
        ),
      ),
    );
  }

  group('PulsingDot Widget', () {
    testWidgets('renders with default emerald color and size', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const PulsingDot(key: Key('test_pulsing_dot')),
        ),
      );

      final dotFinder = find.byKey(const Key('test_pulsing_dot'));
      expect(dotFinder, findsOneWidget);

      // Verify animation ticks forward smoothly without error
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 600));
      expect(dotFinder, findsOneWidget);
    });

    testWidgets('respects custom size and color', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const PulsingDot(
            key: Key('custom_dot'),
            size: 12.0,
            color: HermesColors.amber,
          ),
        ),
      );

      expect(find.byKey(const Key('custom_dot')), findsOneWidget);
    });
  });

  group('GatewayStatusChip Widget', () {
    testWidgets('renders pulsing dot and port running label by default', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const GatewayStatusChip(
            port: 8644,
            isRunning: true,
          ),
        ),
      );

      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(find.byType(PulsingDot), findsOneWidget);
      expect(find.text('Running 8644'), findsOneWidget);
    });

    testWidgets('renders offline state when isRunning is false', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const GatewayStatusChip(
            port: 8644,
            isRunning: false,
          ),
        ),
      );

      expect(find.text('Offline'), findsOneWidget);
    });

    testWidgets('renders custom label when provided', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const GatewayStatusChip(
            customLabel: '● Running 8644',
          ),
        ),
      );

      expect(find.text('● Running 8644'), findsOneWidget);
    });

    testWidgets('triggers onTap callback when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        createTestApp(
          GatewayStatusChip(
            port: 8644,
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('gateway_status_chip')));
      expect(tapped, isTrue);
    });
  });

  group('AchievementTierBadge Widget', () {
    testWidgets('renders lightning bolt icon and default tier progress', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const AchievementTierBadge(
            tier: 'Olympian',
            progress: '47/60 Badges',
          ),
        ),
      );

      expect(find.byKey(const Key('achievement_tier_badge')), findsOneWidget);
      expect(find.byIcon(Icons.bolt), findsOneWidget);
      expect(find.text('Olympian • 47/60 Badges'), findsOneWidget);
    });

    testWidgets('renders custom label when provided', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const AchievementTierBadge(
            customLabel: '⚡ Olympian • 47/60 Badges',
          ),
        ),
      );

      expect(find.text('⚡ Olympian • 47/60 Badges'), findsOneWidget);
    });

    testWidgets('triggers onTap callback when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        createTestApp(
          AchievementTierBadge(
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('achievement_tier_badge')));
      expect(tapped, isTrue);
    });
  });

  group('HeaderConsoleBar Composite Widget', () {
    testWidgets('renders both GatewayStatusChip and AchievementTierBadge in status bar', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const HeaderConsoleBar(
            port: 8644,
            tier: 'Olympian',
            badgeProgress: '47/60 Badges',
          ),
        ),
      );

      expect(find.byKey(const Key('header_console_bar')), findsOneWidget);
      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(find.byKey(const Key('achievement_tier_badge')), findsOneWidget);
      expect(find.text('Running 8644'), findsOneWidget);
      expect(find.text('Olympian • 47/60 Badges'), findsOneWidget);
    });

    testWidgets('does not overflow on narrow mobile screens (320px)', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const HeaderConsoleBar(),
          size: const Size(320, 600),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Verify no RenderFlex overflow error occurs on 320px viewport
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('header_console_bar')), findsOneWidget);
    });
  });
}
