import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/domain/tools/chat/battery_optimization_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_request.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_approval_sheet.dart';
import 'package:flutter_ai_agent/domain/entities/chat/action_step.dart';
import 'package:flutter_ai_agent/domain/entities/chat/generative_card_data.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_confirmation_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/live_action_stepper_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/reasoning_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/summary_card.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/settings_screen.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_routes.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/permission_rationale_modal.dart';
import 'package:flutter_ai_agent/presentation/widget/app_toast.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

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
    when(() => mockAgentCubit.sessions).thenReturn(const []);
    when(() => mockAgentCubit.activeSessionId).thenReturn(null);
    when(() => mockAgentCubit.activeSessionTitle).thenReturn('New chat');
    when(() => mockAgentCubit.refreshSessions()).thenAnswer((_) async {});
    when(() => mockAgentCubit.newChat()).thenAnswer((_) async {});
    when(() => mockAgentCubit.switchSession(any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.renameSession(any(), any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.deleteSession(any())).thenAnswer((_) async {});
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
    AppToast.dismissAll();
    await stateController.close();
    await sl.reset();
  });

  Widget createWidgetUnderTest() {
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          name: AppRoutes.nrChat,
          builder: (context, state) => const ChatScreen(),
        ),
        GoRoute(
          path: '/settings',
          name: AppRoutes.nrSettings,
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      theme: AppTheme.darkTheme,
      routerConfig: router,
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

    testWidgets('renders HeaderConsoleBar with GatewayStatusChip and real connection state pill', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('header_console_bar')), findsOneWidget);
      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('header_console_bar')),
          matching: find.text('Standalone'),
        ),
        findsOneWidget,
      );
      expect(find.text('Running 8644'), findsNothing);
      expect(find.text('Olympian • 47/60 Badges'), findsNothing);
    });

    testWidgets('does not overflow on narrow mobile screens (320x568)', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('chat_app_bar_logo')), findsOneWidget);
      expect(find.text('Flames'), findsOneWidget);
      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(find.byKey(const Key('header_console_bar')), findsOneWidget);
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

    testWidgets('tapping reset button shows confirmation dialog; Cancel does not reset; Reset resets',
        (tester) async {
      when(() => mockAgentCubit.reset()).thenReturn(null);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_reset_button')));
      await tester.pumpAndSettle();

      expect(find.text('Reset Conversation'), findsOneWidget);
      expect(
        find.text(
            'Are you sure you want to reset the conversation and clear history?'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('cancel_reset_button')));
      await tester.pumpAndSettle();
      verifyNever(() => mockAgentCubit.reset());

      await tester.tap(find.byKey(const Key('chat_reset_button')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('confirm_reset_button')));
      await tester.pumpAndSettle();

      verify(() => mockAgentCubit.reset()).called(1);
    });

    testWidgets('settings gear removed from header (owned by bottom nav)', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_settings_button')), findsNothing);
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

    testWidgets('displays top-right toast when AgentError is emitted', (tester) async {
      AppToast.dismissAll();
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      stateController.add(const AgentError('Connection timed out to LLM'));
      await tester.pumpAndSettle();

      expect(find.text('Connection timed out to LLM'), findsOneWidget);
      expect(find.byKey(const Key('app_toast')), findsOneWidget);
      AppToast.dismissAll();
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

    testWidgets('tapping stop button shows confirmation dialog; Cancel does not stop; Stop stops',
        (tester) async {
      when(() => mockAgentCubit.state)
          .thenReturn(const AgentStreaming('partial'));

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();

      await tester.tap(find.byKey(const Key('chat_stop_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Stop Generation'), findsOneWidget);
      expect(
        find.text('Are you sure you want to stop generation?'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('cancel_stop_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      verifyNever(() => mockAgentCubit.stop());

      await tester.tap(find.byKey(const Key('chat_stop_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byKey(const Key('confirm_stop_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      verify(() => mockAgentCubit.stop()).called(1);
    });

    group('Permission Rationale in ChatScreen', () {
      testWidgets(
          'renders Buka Akses button on assistant message when permission denied and opens modal on tap',
          (tester) async {
        when(() => mockAgentCubit.state).thenReturn(
          const AgentSuccess(
            'I cannot complete this action because permission was denied (read_recent_notifications: Permission not granted). Please grant the required permission in device settings to continue.',
            messages: [
              ChatMessage(
                role: 'assistant',
                content:
                    'I cannot complete this action because permission was denied (read_recent_notifications: Permission not granted). Please grant the required permission in device settings to continue.',
              ),
            ],
          ),
        );
        when(() => mockAgentCubit.messages).thenReturn([
          const ChatMessage(
            role: 'assistant',
            content:
                'I cannot complete this action because permission was denied (read_recent_notifications: Permission not granted). Please grant the required permission in device settings to continue.',
          ),
        ]);

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        final buttonFinder =
            find.byKey(const Key('open_permission_rationale_button'));
        expect(buttonFinder, findsWidgets);
        expect(find.text('Buka Akses Notifikasi'), findsWidgets);

        await tester.tap(buttonFinder.first);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(PermissionRationaleModal), findsOneWidget);
        expect(find.text('Akses Notifikasi'), findsWidgets);
      });

      testWidgets(
          'renders security icon and Buka Akses button in tool result card when permission denied',
          (tester) async {
        when(() => mockAgentCubit.state).thenReturn(
          const AgentSuccess(
            'Tool executed',
            messages: [
              ChatMessage(
                role: 'tool',
                name: 'get_location',
                content: 'Error: Permission not granted for get_location',
              ),
            ],
          ),
        );
        when(() => mockAgentCubit.messages).thenReturn([
          const ChatMessage(
            role: 'tool',
            name: 'get_location',
            content: 'Error: Permission not granted for get_location',
          ),
        ]);

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pump();

        expect(find.text('Permission Required: get_location'), findsOneWidget);

        // Tap expansion tile to expand
        await tester.tap(find.text('Permission Required: get_location'));
        await tester.pumpAndSettle();

        final toolBtnFinder =
            find.byKey(const Key('tool_result_permission_button'));
        expect(toolBtnFinder, findsOneWidget);
        expect(find.text('Buka Akses Lokasi'), findsOneWidget);

        await tester.tap(toolBtnFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(PermissionRationaleModal), findsOneWidget);
        expect(find.text('Akses Lokasi'), findsWidgets);
      });
    });

    group('Notification Listener Liveness & Banner', () {
      late MockNotificationTriageService mockTriageService;
      late MockBatteryOptimizationService mockBatteryService;

      setUp(() {
        mockTriageService = MockNotificationTriageService();
        mockBatteryService = MockBatteryOptimizationService();

        when(() => mockTriageService.checkPermission())
            .thenAnswer((_) async => true);
        when(() => mockTriageService.isListenerConnected())
            .thenAnswer((_) async => true);
        when(() => mockTriageService.requestRebind())
            .thenAnswer((_) async => true);
        when(() => mockTriageService.requestPermission())
            .thenAnswer((_) async => true);

        when(() => mockBatteryService.isBatteryOptimizationDisabled())
            .thenAnswer((_) async => const Right(true));
        when(() => mockBatteryService.requestDisableBatteryOptimization())
            .thenAnswer((_) async => const Right(true));

        if (!sl.isRegistered<NotificationTriageServiceBase>()) {
          sl.registerLazySingleton<NotificationTriageServiceBase>(
            () => mockTriageService,
          );
        }
        if (!sl.isRegistered<BatteryOptimizationServiceBase>()) {
          sl.registerLazySingleton<BatteryOptimizationServiceBase>(
            () => mockBatteryService,
          );
        }
      });

      testWidgets(
          'renders tool_result_rebind_button and tapping it calls requestRebind when content contains [listener_not_connected]',
          (tester) async {
        when(() => mockAgentCubit.state).thenReturn(
          const AgentSuccess(
            'Tool executed',
            messages: [
              ChatMessage(
                role: 'tool',
                name: 'read_recent_notifications',
                content:
                    'Error: [listener_not_connected] Notification listener service is disconnected',
              ),
            ],
          ),
        );
        when(() => mockAgentCubit.messages).thenReturn([
          const ChatMessage(
            role: 'tool',
            name: 'read_recent_notifications',
            content:
                'Error: [listener_not_connected] Notification listener service is disconnected',
          ),
        ]);

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        final rebindBtnFinder =
            find.byKey(const Key('tool_result_rebind_button'));
        expect(rebindBtnFinder, findsOneWidget);
        expect(find.text('Hubungkan Ulang Listener'), findsOneWidget);

        await tester.tap(rebindBtnFinder);
        await tester.pumpAndSettle();

        verify(() => mockTriageService.requestRebind()).called(1);
        expect(
          find.text('Listener berhasil terhubung kembali.'),
          findsOneWidget,
        );
      });

      testWidgets(
          'renders notification_listener_warning_banner and tapping rebind button calls requestRebind when listener is not connected',
          (tester) async {
        when(() => mockTriageService.checkPermission())
            .thenAnswer((_) async => true);
        when(() => mockTriageService.isListenerConnected())
            .thenAnswer((_) async => false);
        when(() => mockTriageService.requestRebind())
            .thenAnswer((_) async => true);

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        final bannerFinder =
            find.byKey(const Key('notification_listener_warning_banner'));
        expect(bannerFinder, findsOneWidget);
        expect(find.text('Layanan Notifikasi Terputus'), findsOneWidget);
        expect(
          find.text('Layanan listener tidak aktif di background.'),
          findsOneWidget,
        );

        final bannerRebindBtn =
            find.byKey(const Key('notification_listener_banner_rebind_button'));
        expect(bannerRebindBtn, findsOneWidget);

        await tester.tap(bannerRebindBtn);
        await tester.pumpAndSettle();

        verify(() => mockTriageService.requestRebind()).called(1);
        expect(
          find.text('Listener berhasil terhubung kembali.'),
          findsOneWidget,
        );
      });

      testWidgets('tapping dismiss button hides the notification warning banner',
          (tester) async {
        when(() => mockTriageService.checkPermission())
            .thenAnswer((_) async => true);
        when(() => mockTriageService.isListenerConnected())
            .thenAnswer((_) async => false);

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        final bannerFinder =
            find.byKey(const Key('notification_listener_warning_banner'));
        expect(bannerFinder, findsOneWidget);

        final dismissBtn =
            find.byKey(const Key('notification_listener_banner_dismiss_button'));
        expect(dismissBtn, findsOneWidget);

        await tester.tap(dismissBtn);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('notification_listener_warning_banner')),
          findsNothing,
        );
      });

      testWidgets(
          'shows battery optimization button on warning banner when battery optimization is not exempt',
          (tester) async {
        when(() => mockTriageService.checkPermission())
            .thenAnswer((_) async => true);
        when(() => mockTriageService.isListenerConnected())
            .thenAnswer((_) async => false);
        when(() => mockBatteryService.isBatteryOptimizationDisabled())
            .thenAnswer((_) async => const Right(false));
        when(() => mockBatteryService.requestDisableBatteryOptimization())
            .thenAnswer((_) async => const Right(true));

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        final bannerFinder =
            find.byKey(const Key('notification_listener_warning_banner'));
        expect(bannerFinder, findsOneWidget);
        expect(
          find.text(
            'Layanan listener dihentikan oleh sistem/optimasi baterai Android (MIUI).',
          ),
          findsOneWidget,
        );

        final batteryBtn = find
            .byKey(const Key('notification_listener_banner_battery_button'));
        expect(batteryBtn, findsOneWidget);

        await tester.tap(batteryBtn);
        await tester.pumpAndSettle();

        verify(() => mockBatteryService.requestDisableBatteryOptimization())
            .called(1);
      });

      testWidgets(
          're-checks notification listener and battery state on app resumed lifecycle event',
          (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        clearInteractions(mockTriageService);
        clearInteractions(mockBatteryService);

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await tester.pumpAndSettle();

        verify(() => mockTriageService.checkPermission()).called(1);
        verify(() => mockBatteryService.isBatteryOptimizationDisabled()).called(1);
      });
    });
  });
}
