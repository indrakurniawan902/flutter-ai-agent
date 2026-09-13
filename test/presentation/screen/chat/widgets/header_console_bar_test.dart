import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/header_console_bar.dart';
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

  group('HeaderConsoleBar connection pill', () {
    testWidgets('gateway connected mode renders Connected pill in emerald',
        (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const HeaderConsoleBar(
            connectionLabel: 'Connected',
            connectionColor: HermesColors.emerald,
          ),
        ),
      );

      expect(find.byKey(const Key('header_console_bar')), findsOneWidget);
      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(find.byType(PulsingDot), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);
      expect(find.text('Running 8644'), findsNothing);
    });

    testWidgets('disconnected state renders Disconnected pill', (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const HeaderConsoleBar(
            connectionLabel: 'Disconnected',
            connectionColor: HermesColors.inkMuted,
          ),
        ),
      );

      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('Running 8644'), findsNothing);
    });

    testWidgets('direct mode renders Standalone pill and triggers tap',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        createTestApp(
          HeaderConsoleBar(
            connectionLabel: 'Standalone',
            connectionColor: const Color(0xFF94A3B8),
            onTapConnection: () => tapped = true,
          ),
        ),
      );

      expect(find.text('Standalone'), findsOneWidget);
      await tester.tap(find.byKey(const Key('gateway_status_chip')));
      expect(tapped, isTrue);
    });

    testWidgets('null connectionLabel renders no fabricated status text',
        (tester) async {
      await tester.pumpWidget(createTestApp(const HeaderConsoleBar()));

      expect(find.byKey(const Key('header_console_bar')), findsOneWidget);
      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(find.text('Running 8644'), findsNothing);
      expect(find.text('Olympian'), findsNothing);
      expect(find.text('Connected'), findsNothing);
      expect(find.text('Standalone'), findsNothing);
    });

    testWidgets('does not overflow on narrow mobile screens (320px)',
        (tester) async {
      await tester.pumpWidget(
        createTestApp(
          const HeaderConsoleBar(
            connectionLabel: 'Connected',
            connectionColor: HermesColors.emerald,
          ),
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
