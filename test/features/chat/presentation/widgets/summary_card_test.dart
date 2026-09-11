import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/features/chat/domain/models/generative_card_data.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/summary_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  group('SummaryCard Widget', () {
    testWidgets('renders title, summary text, metric items, and action buttons', (tester) async {
      const data = SummaryCardData(
        title: 'Device Diagnostic Report',
        summaryText: 'Device battery is healthy at 88% and WiFi connectivity is active.',
        items: [
          SummaryMetricItem(label: 'Battery Level', value: '88%'),
          SummaryMetricItem(label: 'Network', value: 'WiFi Connected'),
          SummaryMetricItem(label: 'Tools Executed', value: '2'),
        ],
      );

      await tester.pumpWidget(
        buildTestableWidget(
          const SummaryCard(data: data),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Device Diagnostic Report'), findsOneWidget);
      expect(
        find.text('Device battery is healthy at 88% and WiFi connectivity is active.'),
        findsOneWidget,
      );
      expect(find.text('Battery Level'), findsOneWidget);
      expect(find.text('88%'), findsOneWidget);
      expect(find.text('Network'), findsOneWidget);
      expect(find.text('WiFi Connected'), findsOneWidget);

      expect(find.byKey(const Key('summary_card_copy_btn')), findsOneWidget);
      expect(find.byKey(const Key('summary_card_share_btn')), findsOneWidget);
    });

    testWidgets('single-tap copy button copies summary text to clipboard and invokes callback', (tester) async {
      bool copyCallbackInvoked = false;
      String? copiedClipboardText;

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            final args = methodCall.arguments as Map<dynamic, dynamic>?;
            copiedClipboardText = args?['text'] as String?;
            return null;
          }
          return null;
        },
      );

      const data = SummaryCardData(
        title: 'Execution Summary',
        summaryText: 'Completed 3 background tasks without errors.',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          SummaryCard(
            data: data,
            onCopy: () => copyCallbackInvoked = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('summary_card_copy_btn')));
      await tester.pumpAndSettle();

      expect(copyCallbackInvoked, isTrue);
      expect(copiedClipboardText, equals('Completed 3 background tasks without errors.'));
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('single-tap share button invokes onShare callback', (tester) async {
      bool shareCallbackInvoked = false;
      const data = SummaryCardData(
        title: 'Task Outcome',
        summaryText: 'Event scheduled on calendar.',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          SummaryCard(
            data: data,
            onShare: () => shareCallbackInvoked = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('summary_card_share_btn')));
      await tester.pumpAndSettle();

      expect(shareCallbackInvoked, isTrue);
    });
  });
}
