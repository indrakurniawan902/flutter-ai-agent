import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/features/chat/domain/models/action_step.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/live_action_stepper_card.dart';

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

  group('LiveActionStepperCard Widget', () {
    testWidgets('renders card header, progress ratio, and zero emoji', (tester) async {
      final steps = [
        const ActionStep(
          id: 'step_1',
          title: 'get_device_status',
          status: ActionStepStatus.done,
        ),
        const ActionStep(
          id: 'step_2',
          title: 'get_location',
          status: ActionStepStatus.inProgress,
        ),
        const ActionStep(
          id: 'step_3',
          title: 'send_notification',
          status: ActionStepStatus.pending,
        ),
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          LiveActionStepperCard(
            title: 'Autonomous Action Pipeline',
            steps: steps,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Autonomous Action Pipeline'), findsOneWidget);
      expect(find.text('1/3 Completed'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('renders dynamic step states: done [✔], inProgress [spinner], and pending [ ]', (tester) async {
      final steps = [
        const ActionStep(
          id: 's_done',
          title: 'clipboard_read',
          description: 'Reading clipboard contents',
          status: ActionStepStatus.done,
        ),
        const ActionStep(
          id: 's_progress',
          title: 'camera_take_photo',
          description: 'Accessing camera viewfinder',
          status: ActionStepStatus.inProgress,
        ),
        const ActionStep(
          id: 's_pending',
          title: 'schedule_reminder',
          description: 'Queuing calendar notification',
          status: ActionStepStatus.pending,
        ),
        const ActionStep(
          id: 's_error',
          title: 'system_reboot',
          description: 'Unauthorized command',
          status: ActionStepStatus.error,
          errorMessage: 'Permission denied',
        ),
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          LiveActionStepperCard(steps: steps),
        ),
      );
      await tester.pump(); // Render without settling for infinite animation spinner

      // Done checkmark icon
      expect(find.byIcon(Icons.check_circle), findsOneWidget);

      // In-Progress spinner indicator
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Pending radio/circle icon
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);

      // Error icon
      expect(find.byIcon(Icons.error_outline), findsOneWidget);

      // Titles and descriptions
      expect(find.text('clipboard_read'), findsOneWidget);
      expect(find.text('Reading clipboard contents'), findsOneWidget);
      expect(find.text('camera_take_photo'), findsOneWidget);
      expect(find.text('schedule_reminder'), findsOneWidget);
    });

    testWidgets('expandable accordion toggles tool parameters and output JSON upon tap', (tester) async {
      final steps = [
        const ActionStep(
          id: 'step_accordion',
          title: 'fetch_weather_intel',
          status: ActionStepStatus.done,
          parameters: {'city': 'Jakarta', 'units': 'metric'},
          output: {'temperature': 29, 'condition': 'Sunny'},
        ),
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          LiveActionStepperCard(
            steps: steps,
            initiallyExpanded: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Accordion is initially collapsed
      expect(find.text('Parameters'), findsNothing);
      expect(find.text('Output JSON'), findsNothing);

      // Tap to expand accordion
      await tester.tap(find.text('fetch_weather_intel'));
      await tester.pumpAndSettle();

      // Formatted parameters and output JSON are now visible
      expect(find.text('Parameters'), findsOneWidget);
      expect(find.text('Output JSON'), findsOneWidget);
      expect(find.textContaining('"city": "Jakarta"'), findsOneWidget);
      expect(find.textContaining('"temperature": 29'), findsOneWidget);

      // Tap again to collapse accordion
      await tester.tap(find.text('fetch_weather_intel'));
      await tester.pumpAndSettle();

      expect(find.text('Parameters'), findsNothing);
      expect(find.text('Output JSON'), findsNothing);
    });

    testWidgets('invokes onStepTap callback when step row is tapped', (tester) async {
      ActionStep? tappedStep;
      final steps = [
        const ActionStep(
          id: 'step_callback',
          title: 'sync_memory_vault',
          status: ActionStepStatus.pending,
        ),
      ];

      await tester.pumpWidget(
        buildTestableWidget(
          LiveActionStepperCard(
            steps: steps,
            onStepTap: (step) => tappedStep = step,
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('sync_memory_vault'));
      await tester.pumpAndSettle();

      expect(tappedStep, isNotNull);
      expect(tappedStep!.id, equals('step_callback'));
    });
  });
}
