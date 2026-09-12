import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/core/di/injection_container.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_cubit.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_state.dart';
import 'package:flutter_ai_agent/domain/models/chat/tool_call_request.dart';
import 'package:flutter_ai_agent/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/action_approval_sheet.dart';
import 'package:flutter_ai_agent/domain/models/chat/action_step.dart';
import 'package:flutter_ai_agent/domain/models/chat/generative_card_data.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/action_confirmation_card.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/live_action_stepper_card.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/reasoning_card.dart';
import 'package:flutter_ai_agent/features/chat/presentation/widgets/summary_card.dart';
import 'package:flutter_ai_agent/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:flutter_ai_agent/features/settings/presentation/cubits/settings_state.dart';
import 'package:flutter_ai_agent/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockAgentCubit mockAgentCubit;
  late MockSettingsCubit mockSettingsCubit;
  late StreamController<AgentState> stateController;

  setUp(() async {
    await sl.reset();
    mockAgentCubit = MockAgentCubit();
    mockSettingsCubit = MockSettingsCubit();
    stateController = StreamController<AgentState>.broadcast();

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.messages).thenReturn([]);
    when(() => mockAgentCubit.stream).thenAnswer((_) => stateController.stream);
    when(() => mockAgentCubit.stop()).thenAnswer((_) async {});

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsLoaded(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o',
        temperature: 0.7,
      ),
    );
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());

    sl.registerFactory<AgentCubit>(() => mockAgentCubit);
    sl.registerFactory<SettingsCubit>(() => mockSettingsCubit);
  });

  tearDown(() async {
    await stateController.close();
    await sl.reset();
  });

  Widget createWidgetUnderTest() {
    return const MaterialApp(
      home: ChatScreen(),
    );
  }

  group('ChatScreen - Rendering & Initial State', () {
    testWidgets('renders empty state with Autonomous Device Agent title', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Flames'), findsOneWidget);
      expect(find.text('Autonomous Device Agent'), findsOneWidget);
      expect(find.byKey(const Key('chat_input_field')), findsOneWidget);
      expect(find.byKey(const Key('chat_send_button')), findsOneWidget);
    });

    testWidgets('renders HeaderConsoleBar with GatewayStatusChip and AchievementTierBadge', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('header_console_bar')), findsOneWidget);
      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(find.byKey(const Key('achievement_tier_badge')), findsOneWidget);
      expect(find.text('Running 8644'), findsOneWidget);
      expect(find.text('Olympian • 47/60 Badges'), findsOneWidget);
    });

    testWidgets('send button is disabled when text field is empty', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final iconButton = tester.widget<IconButton>(find.byKey(const Key('chat_send_button')));
      expect(iconButton.onPressed, isNull);
    });

    testWidgets('typing enables send button and tapping send calls sendMessage', (tester) async {
      when(() => mockAgentCubit.sendMessage(any())).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('chat_input_field')), 'Hello Agent');
      await tester.pump();

      final iconButton = tester.widget<IconButton>(find.byKey(const Key('chat_send_button')));
      expect(iconButton.onPressed, isNotNull);

      await tester.tap(find.byKey(const Key('chat_send_button')));
      await tester.pump();

      verify(() => mockAgentCubit.sendMessage('Hello Agent')).called(1);
      expect(find.text('Hello Agent'), findsNothing); // TextField cleared
    });

    testWidgets('tapping reset button calls cubit.reset()', (tester) async {
      when(() => mockAgentCubit.reset()).thenReturn(null);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_reset_button')));
      await tester.pump();

      verify(() => mockAgentCubit.reset()).called(1);
    });

    testWidgets('tapping settings button navigates to SettingsScreen', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_settings_button')));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsScreen), findsOneWidget);
    });
  });

  group('ChatScreen - Message History & States', () {
    testWidgets('renders user messages and assistant messages with markdown', (tester) async {
      when(() => mockAgentCubit.messages).thenReturn([
        const ChatMessage(role: 'user', content: 'What is the capital of France?'),
        const ChatMessage(role: 'assistant', content: 'The capital of **France** is Paris.'),
      ]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('What is the capital of France?'), findsOneWidget);
      expect(find.textContaining('Paris'), findsOneWidget);
    });

    testWidgets('renders streaming bubble with partial text when AgentStreaming emitted', (tester) async {
      when(() => mockAgentCubit.messages).thenReturn([
        const ChatMessage(role: 'user', content: 'Tell me a story'),
      ]);
      when(() => mockAgentCubit.state).thenReturn(
        const AgentStreaming('Once upon a time in a digital world'),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.text('Once upon a time in a digital world'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders tool call and tool result cards and expands JSON content', (tester) async {
      when(() => mockAgentCubit.messages).thenReturn([
        const ChatMessage(
          role: 'assistant',
          toolCalls: [
            ToolCallDelta(
              index: 0,
              id: 'call_1',
              name: 'get_location',
              argumentsFragment: '{"accuracy": "high"}',
            ),
          ],
        ),
        const ChatMessage(
          role: 'tool',
          toolCallId: 'call_1',
          name: 'get_location',
          content: '{"latitude": 37.7749, "longitude": -122.4194}',
        ),
      ]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Tool: get_location'), findsOneWidget);
      expect(find.text('Result: get_location'), findsOneWidget);

      // Expand tool call card to inspect arguments JSON
      await tester.tap(find.text('Tool: get_location'));
      await tester.pumpAndSettle();
      expect(find.text('{"accuracy": "high"}'), findsOneWidget);

      // Expand tool result card to inspect result JSON
      await tester.tap(find.text('Result: get_location'));
      await tester.pumpAndSettle();
      expect(
        find.text('{"latitude": 37.7749, "longitude": -122.4194}'),
        findsOneWidget,
      );
    });

    testWidgets('renders ExecutingTool indicator when tool is running', (tester) async {
      when(() => mockAgentCubit.state).thenReturn(
        const ExecutingTool('camera_take_photo'),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.text('Running camera_take_photo...'), findsOneWidget);
    });

    testWidgets('renders thinking indicator when AgentThinking is emitted', (tester) async {
      when(() => mockAgentCubit.state).thenReturn(const AgentThinking());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.text('Thinking...'), findsOneWidget);
    });

    testWidgets('shows ActionApprovalSheet on WaitingApproval and triggers approveAction', (tester) async {
      when(() => mockAgentCubit.approveAction()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      stateController.add(
        const WaitingApproval(
          ToolCallRequest(
            id: 'call_hitl_1',
            name: 'schedule_reminder',
            parameters: {'title': 'Doctor Appointment', 'delayMinutes': 30},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ActionApprovalSheet), findsOneWidget);
      expect(find.text('schedule_reminder'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() => mockAgentCubit.approveAction()).called(1);
    });

    testWidgets('shows ActionApprovalSheet on WaitingApproval and triggers rejectAction', (tester) async {
      when(() => mockAgentCubit.rejectAction()).thenAnswer((_) async {});

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      stateController.add(
        const WaitingApproval(
          ToolCallRequest(
            id: 'call_hitl_2',
            name: 'schedule_reminder',
            parameters: {'title': 'Delete files', 'delayMinutes': 10},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ActionApprovalSheet), findsOneWidget);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      verify(() => mockAgentCubit.rejectAction()).called(1);
    });

    testWidgets('displays SnackBar when AgentError is emitted', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      stateController.add(const AgentError('Connection timed out to LLM'));
      await tester.pumpAndSettle();

      expect(find.text('Connection timed out to LLM'), findsOneWidget);
      expect(find.byType(SnackBar), findsOneWidget);
    });

    testWidgets('renders LiveActionStepperCard in chat stream and toggles accordion upon tap', (tester) async {
      when(() => mockAgentCubit.messages).thenReturn([
        const ChatMessage(
          role: 'assistant',
          actionSteps: [
            ActionStep(
              id: 'st_1',
              title: 'read_clipboard_intel',
              description: 'Reading clipboard payload',
              status: ActionStepStatus.done,
              output: {'content': 'Hermes token'},
            ),
            ActionStep(
              id: 'st_2',
              title: 'query_context_diagnostics',
              description: 'Checking battery and sensors',
              status: ActionStepStatus.inProgress,
              parameters: {'deep': true},
            ),
            ActionStep(
              id: 'st_3',
              title: 'sync_telemetry_vault',
              status: ActionStepStatus.pending,
            ),
          ],
        ),
      ]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(LiveActionStepperCard), findsOneWidget);
      expect(find.text('read_clipboard_intel'), findsOneWidget);
      expect(find.text('query_context_diagnostics'), findsOneWidget);
      expect(find.text('sync_telemetry_vault'), findsOneWidget);

      // Step states
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);

      // Accordion toggle on tap
      await tester.tap(find.text('read_clipboard_intel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Output JSON'), findsOneWidget);
      expect(find.textContaining('Hermes token'), findsOneWidget);
    });

    testWidgets('renders ActionConfirmationCard in chat stream and triggers cubit approve action', (tester) async {
      when(() => mockAgentCubit.approveAction()).thenAnswer((_) async {});
      when(() => mockAgentCubit.messages).thenReturn([
        const ChatMessage(
          role: 'assistant',
          confirmationCard: ActionConfirmationData(
            title: 'Authorize Calendar Event',
            message: 'Agent requests permission to add event to Google Calendar.',
            primaryActionLabel: 'Grant Access',
            secondaryActionLabel: 'Deny Access',
          ),
        ),
      ]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byType(ActionConfirmationCard), findsOneWidget);
      expect(find.text('Authorize Calendar Event'), findsOneWidget);
      expect(find.text('Grant Access'), findsOneWidget);

      await tester.tap(find.byKey(const Key('action_confirmation_primary_btn')));
      await tester.pumpAndSettle();

      verify(() => mockAgentCubit.approveAction()).called(1);
    });

    testWidgets('renders SummaryCard in chat stream and triggers copy button', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (MethodCall methodCall) async {
          if (methodCall.method == 'Clipboard.setData') {
            return null;
          }
          return null;
        },
      );

      when(() => mockAgentCubit.messages).thenReturn([
        const ChatMessage(
          role: 'assistant',
          summaryCard: SummaryCardData(
            title: 'Autonomous Execution Summary',
            summaryText: 'All requested actions completed cleanly.',
            items: [
              SummaryMetricItem(label: 'Tools Called', value: '3'),
              SummaryMetricItem(label: 'Total Time', value: '450ms'),
            ],
          ),
        ),
      ]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byType(SummaryCard), findsOneWidget);
      expect(find.text('Autonomous Execution Summary'), findsOneWidget);
      expect(find.text('Tools Called'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);

      await tester.tap(find.byKey(const Key('summary_card_copy_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('renders ReasoningCard above assistant bubble when thoughtProcess is present', (tester) async {
      when(() => mockAgentCubit.messages).thenReturn([
        const ChatMessage(
          role: 'assistant',
          thoughtProcess: 'Analyzing the query\nFormulating response',
          content: 'Here is the answer.',
        ),
      ]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byType(ReasoningCard), findsOneWidget);
      expect(find.text('Thought Process'), findsOneWidget);
      expect(find.text('Here is the answer.'), findsOneWidget);

      // By default ReasoningCard is collapsed, so thought text is not displayed
      expect(find.text('Analyzing the query\nFormulating response'), findsNothing);

      // Tap to expand
      await tester.tap(find.byKey(const Key('reasoning_card_header')));
      await tester.pumpAndSettle();

      expect(find.text('Analyzing the query\nFormulating response'), findsOneWidget);
    });
  });

  group('ChatScreen - Stop Generation', () {
    testWidgets('stop button is not rendered when state is AgentIdle',
        (tester) async {
      when(() => mockAgentCubit.state).thenReturn(const AgentIdle());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.byKey(const Key('chat_stop_button')), findsNothing);
    });

    testWidgets('stop button is rendered when state is AgentThinking',
        (tester) async {
      when(() => mockAgentCubit.state).thenReturn(const AgentThinking());

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.byKey(const Key('chat_stop_button')), findsOneWidget);
    });

    testWidgets('stop button is rendered when state is AgentStreaming',
        (tester) async {
      when(() => mockAgentCubit.state)
          .thenReturn(const AgentStreaming('partial'));

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.byKey(const Key('chat_stop_button')), findsOneWidget);
    });

    testWidgets('stop button is rendered when state is ExecutingTool',
        (tester) async {
      when(() => mockAgentCubit.state)
          .thenReturn(const ExecutingTool('get_location'));

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      expect(find.byKey(const Key('chat_stop_button')), findsOneWidget);
    });

    testWidgets('tapping stop button calls cubit.stop()', (tester) async {
      when(() => mockAgentCubit.state)
          .thenReturn(const AgentStreaming('partial'));

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      await tester.tap(find.byKey(const Key('chat_stop_button')));
      await tester.pump();

      verify(() => mockAgentCubit.stop()).called(1);
    });
  });
}
