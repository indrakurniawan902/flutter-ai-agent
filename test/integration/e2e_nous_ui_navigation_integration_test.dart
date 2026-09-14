import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/myapp.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_router.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/models/chat/action_step.dart';
import 'package:flutter_ai_agent/domain/models/chat/generative_card_data.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_confirmation_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/header_console_bar.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/live_action_stepper_card.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/summary_card.dart';
import 'package:flutter_ai_agent/presentation/screen/memory_vault/memory_vault_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/navigation/cubit/navigation_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/navigation/main_navigation_shell.dart';
import 'package:flutter_ai_agent/presentation/widget/floating_bottom_nav_bar.dart';
import 'package:flutter_ai_agent/presentation/screen/pocket_node/pocket_node_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/settings_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/skills_hub_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late MockAgentCubit mockAgentCubit;
  late MockSettingsCubit mockSettingsCubit;
  late MockServerProfileCubit mockServerProfileCubit;
  late StreamController<AgentState> agentStateController;
  late List<ChatMessage> inMemoryMessages;

  setUp(() async {
    await sl.reset();
    inMemoryMessages = [];
    agentStateController = StreamController<AgentState>.broadcast();

    mockAgentCubit = MockAgentCubit();
    mockSettingsCubit = MockSettingsCubit();
    mockServerProfileCubit = MockServerProfileCubit();

    // Default agent cubit mock behaviors
    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.sessions).thenReturn(const []);
    when(() => mockAgentCubit.activeSessionId).thenReturn(null);
    when(() => mockAgentCubit.activeSessionTitle).thenReturn('New chat');
    when(() => mockAgentCubit.refreshSessions()).thenAnswer((_) async {});
    when(() => mockAgentCubit.newChat()).thenAnswer((_) async {});
    when(() => mockAgentCubit.switchSession(any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.renameSession(any(), any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.deleteSession(any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.messages).thenAnswer((_) => inMemoryMessages);
    when(() => mockAgentCubit.stream).thenAnswer((_) => agentStateController.stream);
    when(() => mockAgentCubit.reset()).thenAnswer((_) {
      inMemoryMessages.clear();
      mockAgentCubit.emit(const AgentIdle());
    });
    when(() => mockAgentCubit.sendMessage(any())).thenAnswer((inv) async {
      final prompt = inv.positionalArguments[0] as String;
      inMemoryMessages.add(ChatMessage(role: 'user', content: prompt));
    });

    // Default settings cubit mock behaviors
    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsLoaded(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-hermes-e2e-test',
        model: 'ag-glm',
        temperature: 0.7,
      ),
    );
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());

    // Default server profiles cubit mock behaviors
    when(() => mockServerProfileCubit.state).thenReturn(
      const ServerProfileLoaded(profiles: []),
    );
    when(() => mockServerProfileCubit.stream).thenAnswer((_) => const Stream.empty());

    // Register into GetIt service locator
    sl.registerFactory<AgentCubit>(() => mockAgentCubit);
    sl.registerFactory<SettingsCubit>(() => mockSettingsCubit);
    sl.registerFactory<ServerProfileCubit>(() => mockServerProfileCubit);
    sl.registerFactory<NavigationCubit>(() => NavigationCubit());

    appRouter.go('/splash');
  });

  void setTestScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  tearDown(() async {
    if (!agentStateController.isClosed) {
      await agentStateController.close();
    }
    await sl.reset();
  });

  group('Fase 5 E2E: 5-Tab Navigation Cycle & Hermes Nous Theme', () {
    testWidgets(
      'Full 5-tab navigation cycle with Hermes Nous visual tokens and zero emoji',
      (tester) async {
        setTestScreen(tester);
        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        // 1. Verify Root App & Dark Theme
        final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
        expect(materialApp.theme?.brightness, Brightness.dark);
        expect(find.byType(MainNavigationShell), findsOneWidget);
        expect(find.byType(FloatingBottomNavBar), findsOneWidget);

        // 2. Tab 0: ChatScreen Verification
        expect(find.byType(ChatScreen), findsOneWidget);
        expect(find.byType(HeaderConsoleBar), findsOneWidget);
        expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
        expect(find.byType(PulsingDot), findsOneWidget);
        expect(find.textContaining('Running 8644'), findsNothing);
        expect(find.textContaining('Olympian'), findsNothing);

        // 3. Tab 0 -> Tab 1: Skills Hub
        await tester.tap(find.byKey(const Key('nav_item_skills')));
        await tester.pumpAndSettle();

        expect(find.byType(SkillsHubScreen), findsOneWidget);
        expect(find.text('Skills Hub'), findsOneWidget);
        expect(find.byKey(const Key('skills_search_field')), findsOneWidget);
        expect(find.byKey(const Key('skills_filter_pill_all')), findsOneWidget);
        expect(find.byKey(const Key('skills_filter_pill_device')), findsOneWidget);
        expect(find.byKey(const Key('skills_filter_pill_automations')), findsOneWidget);
        expect(find.byKey(const Key('skills_filter_pill_system')), findsOneWidget);
        expect(find.byKey(const Key('skills_filter_pill_vision')), findsOneWidget);
        expect(find.text('camera_vision'), findsOneWidget);

        // 4. Tab 1 -> Tab 2: Pocket Node
        await tester.tap(find.byKey(const Key('nav_item_node')));
        await tester.pumpAndSettle();

        expect(find.byType(PocketNodeScreen), findsOneWidget);
        expect(find.text('Pocket Node'), findsOneWidget);
        expect(find.text('RPC Node Telemetry'), findsOneWidget);
        expect(find.textContaining('Ambient Triggers'), findsOneWidget);
        expect(find.byKey(const Key('ambient_trigger_geofence')), findsOneWidget);
        expect(find.byKey(const Key('ambient_trigger_battery')), findsOneWidget);
        expect(find.byKey(const Key('switch_geofence')), findsOneWidget);
        expect(find.byKey(const Key('node_rpc_telemetry_card')), findsOneWidget);

        // 5. Tab 2 -> Tab 3: Memory Vault
        await tester.tap(find.byKey(const Key('nav_item_vault')));
        await tester.pumpAndSettle();

        expect(find.byType(MemoryVaultScreen), findsOneWidget);
        expect(find.text('Memory Vault'), findsOneWidget);
        expect(find.textContaining('FTS5 Indexed'), findsOneWidget);
        expect(find.byKey(const Key('memory_search_input')), findsOneWidget);

        // 6. Tab 3 -> Tab 4: Settings Screen
        await tester.tap(find.byKey(const Key('nav_item_settings')));
        await tester.pumpAndSettle();

        expect(find.byType(SettingsScreen), findsOneWidget);
        expect(find.text('LLM Settings'), findsOneWidget);
        expect(find.byKey(const Key('settings_base_url_field')), findsOneWidget);
        expect(find.byKey(const Key('settings_api_key_field')), findsOneWidget);
        expect(find.byKey(const Key('settings_model_field')), findsOneWidget);
        expect(find.byKey(const Key('settings_temperature_field')), findsOneWidget);

        // 7. Tab 4 -> Tab 0: Return to ChatScreen
        await tester.tap(find.byKey(const Key('nav_item_chat')));
        await tester.pumpAndSettle();

        expect(find.byType(ChatScreen), findsOneWidget);
        expect(find.text('Flames'), findsOneWidget);
      },
    );

    testWidgets(
      'Cross-tab persistent state retention across full 5-tab cycle',
      (tester) async {
        setTestScreen(tester);
        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        // 1. Enter draft text in Chat Tab (Tab 0)
        const chatDraftText = 'Persistent prompt state testing for Hermes Nous UI';
        await tester.enterText(find.byKey(const Key('chat_input_field')), chatDraftText);
        await tester.pump();

        final chatFieldBefore = tester.widget<TextField>(find.byKey(const Key('chat_input_field')));
        expect(chatFieldBefore.controller?.text, chatDraftText);

        // 2. Switch to Tab 1 (Skills Hub) and apply category filter
        await tester.tap(find.byKey(const Key('nav_item_skills')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('skills_filter_pill_device')));
        await tester.pumpAndSettle();

        expect(find.text('location_context'), findsOneWidget);
        expect(find.text('camera_vision'), findsNothing);

        // 3. Switch to Tab 3 (Memory Vault) and type search query
        await tester.tap(find.byKey(const Key('nav_item_vault')));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('memory_search_input')), 'router');
        await tester.pumpAndSettle();

        // Seed records were purged (T19.5), so an empty vault is expected;
        // this assertion only guards that the vault tab rendered its list area.
        expect(find.byKey(const Key('memory_empty_state')), findsOneWidget);

        // 4. Switch to Tab 2 (Pocket Node)
        await tester.tap(find.byKey(const Key('nav_item_node')));
        await tester.pumpAndSettle();
        expect(find.text('Pocket Node'), findsOneWidget);

        // 5. Switch to Tab 4 (Settings)
        await tester.tap(find.byKey(const Key('nav_item_settings')));
        await tester.pumpAndSettle();
        expect(find.text('LLM Settings'), findsOneWidget);

        // 6. Return to Tab 0 (Chat) -> Verify chat draft input is 100% retained
        await tester.tap(find.byKey(const Key('nav_item_chat')));
        await tester.pumpAndSettle();

        final chatFieldAfter = tester.widget<TextField>(find.byKey(const Key('chat_input_field')));
        expect(chatFieldAfter.controller?.text, chatDraftText);

        // 7. Return to Tab 1 (Skills Hub) -> Verify filter is retained
        await tester.tap(find.byKey(const Key('nav_item_skills')));
        await tester.pumpAndSettle();
        expect(find.text('location_context'), findsOneWidget);
        expect(find.text('camera_vision'), findsNothing);

        // 8. Return to Tab 3 (Memory Vault) -> Verify search query is retained
        await tester.tap(find.byKey(const Key('nav_item_vault')));
        await tester.pumpAndSettle();
        final vaultFieldAfter = tester.widget<TextField>(find.byKey(const Key('memory_search_input')));
        expect(vaultFieldAfter.controller?.text, 'router');
      },
    );
  });

  group('Fase 5 E2E: Chat Streaming, ReAct Loop & Stepper Cards', () {
    testWidgets(
      'Chat streaming renders LiveActionStepperCard with dynamic steps, accordion, and zero emoji',
      (tester) async {
        setTestScreen(tester);

        inMemoryMessages.addAll([
          const ChatMessage(
            role: 'user',
            content: 'Check device telemetry and format report',
          ),
          const ChatMessage(
            role: 'assistant',
            content: 'Executing diagnostics pipeline...',
            actionSteps: [
              ActionStep(
                id: 'step_1',
                title: 'device_status_read',
                description: 'Querying battery and connectivity',
                status: ActionStepStatus.done,
                parameters: {'battery': true, 'connectivity': true},
                output: {'battery': 92, 'charging': true, 'wifi': 'Home-WiFi'},
              ),
              ActionStep(
                id: 'step_2',
                title: 'clipboard_intel_sync',
                description: 'Reading scratchpad clipboard',
                status: ActionStepStatus.inProgress,
                parameters: {'target': 'latest_snippet'},
              ),
              ActionStep(
                id: 'step_3',
                title: 'memory_vault_append',
                description: 'Persisting execution telemetry',
                status: ActionStepStatus.pending,
              ),
            ],
          ),
        ]);

        appRouter.go('/home');
        await tester.pumpWidget(const App());
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        // 1. Verify Stepper Card renders
        expect(find.byType(LiveActionStepperCard), findsOneWidget);
        expect(find.text('Action Execution Pipeline'), findsOneWidget);
        expect(find.text('1/3 Completed'), findsOneWidget);

        // 2. Verify individual steps and zero-emoji icons
        expect(find.text('device_status_read'), findsOneWidget);
        expect(find.text('clipboard_intel_sync'), findsOneWidget);
        expect(find.text('memory_vault_append'), findsOneWidget);

        expect(find.byIcon(Icons.check_circle), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byIcon(Icons.radio_button_unchecked), findsOneWidget);

        // 3. Expand accordion on step 1 to inspect JSON parameters and outputs
        await tester.tap(find.text('device_status_read'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Parameters'), findsOneWidget);
        expect(find.text('Output JSON'), findsOneWidget);
        expect(find.textContaining('Home-WiFi'), findsOneWidget);

        // 4. Update state with final assistant text response
        inMemoryMessages.add(
          const ChatMessage(
            role: 'assistant',
            content: '### Telemetry Report Complete\n- Battery: **92%** (Charging)\n- Wi-Fi: **Connected**',
          ),
        );
        agentStateController.add(
          AgentSuccess(
            '### Telemetry Report Complete\n- Battery: **92%** (Charging)\n- Wi-Fi: **Connected**',
            messages: inMemoryMessages,
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.textContaining('Telemetry Report Complete'), findsOneWidget);
        expect(find.textContaining('Battery:'), findsOneWidget);
      },
    );

    testWidgets(
      'Generative micro-UI cards (ActionConfirmationCard & SummaryCard) render and trigger actions',
      (tester) async {
        setTestScreen(tester);

        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall methodCall) async {
            if (methodCall.method == 'Clipboard.setData') {
              return null;
            }
            return null;
          },
        );

        var confirmed = false;

        when(() => mockAgentCubit.approveAction()).thenAnswer((_) async {
          confirmed = true;
        });

        inMemoryMessages.addAll([
          const ChatMessage(
            role: 'user',
            content: 'Schedule reminder and generate summary',
          ),
          const ChatMessage(
            role: 'assistant',
            confirmationCard: ActionConfirmationData(
              title: 'Confirm Calendar Event',
              message: 'Agent requests permission to add "Project Standup" to calendar.',
              primaryActionLabel: 'Authorize',
              secondaryActionLabel: 'Decline',
              tierLabel: 'Tier 3 (State Modifying)',
              parameters: {
                'event': 'Project Standup',
                'time': '10:00 AM',
                'duration': '30m',
              },
            ),
            summaryCard: SummaryCardData(
              title: 'Execution Summary',
              summaryText: 'All pipeline tasks verified with 0 failures.',
              items: [
                SummaryMetricItem(label: 'Tools Run', value: '4'),
                SummaryMetricItem(label: 'Duration', value: '320ms'),
                SummaryMetricItem(label: 'Status', value: '100% Green'),
              ],
            ),
          ),
        ]);

        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        // 1. Verify ActionConfirmationCard renders
        expect(find.byType(ActionConfirmationCard), findsOneWidget);
        expect(find.text('Confirm Calendar Event'), findsOneWidget);
        expect(find.text('Tier 3 (State Modifying)'), findsOneWidget);
        expect(find.text('Authorize'), findsOneWidget);
        expect(find.text('Decline'), findsOneWidget);
        expect(find.textContaining('Project Standup'), findsWidgets);

        // 2. Verify SummaryCard renders
        expect(find.byType(SummaryCard), findsOneWidget);
        expect(find.text('Execution Summary'), findsOneWidget);
        expect(find.text('Tools Run'), findsOneWidget);
        expect(find.text('4'), findsOneWidget);
        expect(find.text('320ms'), findsOneWidget);
        expect(find.text('100% Green'), findsOneWidget);

        // 3. Tap Authorize button on confirmation card -> calls cubit approveAction
        final primaryBtn = find.byKey(const Key('action_confirmation_primary_btn'));
        await tester.ensureVisible(primaryBtn);
        await tester.pumpAndSettle();
        await tester.tap(primaryBtn);
        await tester.pumpAndSettle();
        expect(confirmed, isTrue);

        // 4. Tap copy button on SummaryCard
        final copyBtn = find.byKey(const Key('summary_card_copy_btn'));
        await tester.ensureVisible(copyBtn);
        await tester.pumpAndSettle();
        await tester.tap(copyBtn);
        await tester.pumpAndSettle();
        expect(find.text('Copied'), findsOneWidget);
      },
    );

    testWidgets(
      'Tab switching resilience preserves active conversation and micro-UI cards',
      (tester) async {
        setTestScreen(tester);

        inMemoryMessages.addAll([
          const ChatMessage(role: 'user', content: 'Initial question'),
          const ChatMessage(
            role: 'assistant',
            content: 'Detailed assistant answer with tools.',
            actionSteps: [
              ActionStep(
                id: 'st_step',
                title: 'read_status',
                status: ActionStepStatus.done,
                output: 'OK',
              ),
            ],
          ),
        ]);

        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        expect(find.text('Initial question'), findsOneWidget);
        expect(find.byType(LiveActionStepperCard), findsOneWidget);

        // Switch to Tab 1 (Skills)
        await tester.tap(find.byKey(const Key('nav_item_skills')));
        await tester.pumpAndSettle();
        expect(find.text('Skills Hub'), findsOneWidget);

        // Switch to Tab 2 (Node)
        await tester.tap(find.byKey(const Key('nav_item_node')));
        await tester.pumpAndSettle();
        expect(find.text('Pocket Node'), findsOneWidget);

        // Switch back to Tab 0 (Chat)
        await tester.tap(find.byKey(const Key('nav_item_chat')));
        await tester.pumpAndSettle();

        // Verify conversation and stepper are still completely visible and responsive
        expect(find.text('Initial question'), findsOneWidget);
        expect(find.byType(LiveActionStepperCard), findsOneWidget);
        expect(find.byType(HeaderConsoleBar), findsOneWidget);
      },
    );
  });
}
