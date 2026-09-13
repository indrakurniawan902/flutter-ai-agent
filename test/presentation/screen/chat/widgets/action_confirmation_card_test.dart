import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/domain/entities/chat/generative_card_data.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_confirmation_card.dart';

void main() {
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

  group('ActionConfirmationCard Widget', () {
    testWidgets('renders title, message, tier badge, parameters, and zero emojis', (tester) async {
      const data = ActionConfirmationData(
        title: 'Schedule System Notification',
        message: 'Agent will post a reminder to system tray in 15 minutes.',
        tierLabel: 'Tier 3 HITL Gate',
        parameters: {'delayMinutes': 15, 'title': 'Meeting'},
        primaryActionLabel: 'Approve Schedule',
        secondaryActionLabel: 'Dismiss',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          const ActionConfirmationCard(data: data),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Schedule System Notification'), findsOneWidget);
      expect(
        find.text('Agent will post a reminder to system tray in 15 minutes.'),
        findsOneWidget,
      );
      expect(find.text('Tier 3 HITL Gate'), findsOneWidget);
      expect(find.text('Approve Schedule'), findsOneWidget);
      expect(find.text('Dismiss'), findsOneWidget);
      expect(find.textContaining('"delayMinutes": 15'), findsOneWidget);
    });

    testWidgets('tapping primary button triggers onConfirm callback', (tester) async {
      bool confirmed = false;
      const data = ActionConfirmationData(
        title: 'Camera Capture',
        message: 'Agent needs to capture an image.',
        primaryActionLabel: 'Authorize Camera',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          ActionConfirmationCard(
            data: data,
            onConfirm: () => confirmed = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('action_confirmation_primary_btn')));
      await tester.pumpAndSettle();

      expect(confirmed, isTrue);
    });

    testWidgets('tapping secondary button triggers onCancel callback', (tester) async {
      bool cancelled = false;
      const data = ActionConfirmationData(
        title: 'Delete History',
        message: 'Are you sure you want to clear session history?',
        secondaryActionLabel: 'Reject Action',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          ActionConfirmationCard(
            data: data,
            onCancel: () => cancelled = true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('action_confirmation_secondary_btn')));
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
    });

    testWidgets('shows loading indicator and disables buttons when isLoading is true', (tester) async {
      bool tapped = false;
      const data = ActionConfirmationData(
        title: 'Running Operation',
        message: 'Executing authorized operation...',
      );

      await tester.pumpWidget(
        buildTestableWidget(
          ActionConfirmationCard(
            data: data,
            isLoading: true,
            onConfirm: () => tapped = true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.byKey(const Key('action_confirmation_primary_btn')));
      await tester.pump();

      expect(tapped, isFalse);
    });

    testWidgets('displays confirmed badge when isConfirmed is true', (tester) async {
      const data = ActionConfirmationData(
        title: 'Sync Database',
        message: 'Synchronizing SQLite tables.',
        isConfirmed: true,
      );

      await tester.pumpWidget(
        buildTestableWidget(
          const ActionConfirmationCard(data: data),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Action Confirmed'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
    });
  });
}
