import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/di/injection_container.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_cubit.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_state.dart';
import 'package:flutter_ai_agent/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter_ai_agent/features/memory_vault/presentation/screens/memory_vault_screen.dart';
import 'package:flutter_ai_agent/features/navigation/presentation/cubits/navigation_cubit.dart';
import 'package:flutter_ai_agent/features/navigation/presentation/screens/main_navigation_shell.dart';
import 'package:flutter_ai_agent/features/pocket_node/presentation/screens/pocket_node_screen.dart';
import 'package:flutter_ai_agent/features/server_profiles/presentation/cubits/server_profile_cubit.dart';
import 'package:flutter_ai_agent/features/server_profiles/presentation/cubits/server_profile_state.dart';
import 'package:flutter_ai_agent/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:flutter_ai_agent/features/settings/presentation/cubits/settings_state.dart';
import 'package:flutter_ai_agent/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_ai_agent/features/skills/presentation/screens/skills_hub_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockAgentCubit mockAgentCubit;
  late MockSettingsCubit mockSettingsCubit;
  late MockServerProfileCubit mockServerProfileCubit;
  late StreamController<AgentState> agentStateController;

  setUp(() async {
    await sl.reset();
    mockAgentCubit = MockAgentCubit();
    mockSettingsCubit = MockSettingsCubit();
    mockServerProfileCubit = MockServerProfileCubit();
    agentStateController = StreamController<AgentState>.broadcast();

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.messages).thenReturn([]);
    when(() => mockAgentCubit.stream).thenAnswer((_) => agentStateController.stream);

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsLoaded(
        baseUrl: 'https://indra-9router.my.id/v1',
        apiKey: 'sk-test',
        model: 'ag-glm',
        temperature: 0.7,
      ),
    );
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockServerProfileCubit.state).thenReturn(
      const ServerProfileLoaded(profiles: []),
    );
    when(() => mockServerProfileCubit.stream).thenAnswer((_) => const Stream.empty());

    sl.registerFactory<AgentCubit>(() => mockAgentCubit);
    sl.registerFactory<SettingsCubit>(() => mockSettingsCubit);
    sl.registerFactory<ServerProfileCubit>(() => mockServerProfileCubit);
    sl.registerFactory<NavigationCubit>(() => NavigationCubit());
  });

  tearDown(() async {
    await agentStateController.close();
    await sl.reset();
  });

  Widget createWidgetUnderTest({NavigationCubit? cubit}) {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: MainNavigationShell(cubit: cubit),
    );
  }

  group('MainNavigationShell - Shell & Tab Rendering', () {
    testWidgets('renders shell with IndexedStack, 5 tabs, and FloatingBottomNavBar', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byType(MainNavigationShell), findsOneWidget);
      expect(find.byKey(const Key('main_navigation_shell')), findsOneWidget);
      expect(find.byKey(const Key('main_navigation_indexed_stack')), findsOneWidget);
      expect(find.byKey(const Key('floating_bottom_nav_bar')), findsOneWidget);

      final indexedStack = tester.widget<IndexedStack>(find.byKey(const Key('main_navigation_indexed_stack')));
      expect(indexedStack.children.length, 5);
      expect(indexedStack.index, 0);

      // Tab 1 is visible by default
      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.text('Flames'), findsOneWidget);
    });

    testWidgets('switching tabs updates active screen', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Tap Tab 2: Skills
      await tester.tap(find.byKey(const Key('nav_item_skills')));
      await tester.pumpAndSettle();
      expect(find.text('Skills Hub'), findsOneWidget);
      expect(find.byType(SkillsHubScreen), findsOneWidget);

      // Tap Tab 3: Node
      await tester.tap(find.byKey(const Key('nav_item_node')));
      await tester.pumpAndSettle();
      expect(find.text('Pocket Node'), findsOneWidget);
      expect(find.byType(PocketNodeScreen), findsOneWidget);

      // Tap Tab 4: Vault
      await tester.tap(find.byKey(const Key('nav_item_vault')));
      await tester.pumpAndSettle();
      expect(find.text('Memory Vault'), findsOneWidget);
      expect(find.byType(MemoryVaultScreen), findsOneWidget);

      // Tap Tab 5: Settings
      await tester.tap(find.byKey(const Key('nav_item_settings')));
      await tester.pumpAndSettle();
      expect(find.text('LLM Settings'), findsOneWidget);
      expect(find.byType(SettingsScreen), findsOneWidget);

      // Tap back to Tab 1: Chat
      await tester.tap(find.byKey(const Key('nav_item_chat')));
      await tester.pumpAndSettle();
      expect(find.text('Flames'), findsOneWidget);
      expect(find.byType(ChatScreen), findsOneWidget);
    });
  });

  group('MainNavigationShell - State Retention Verification', () {
    testWidgets('preserves chat input state when switching between tabs', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // On Tab 1: ChatScreen, type input
      const testPrompt = 'Persistent state preservation test prompt';
      await tester.enterText(find.byKey(const Key('chat_input_field')), testPrompt);
      await tester.pump();

      final inputFieldBefore = tester.widget<TextField>(find.byKey(const Key('chat_input_field')));
      expect(inputFieldBefore.controller?.text, testPrompt);

      // Switch to Tab 2: Skills
      await tester.tap(find.byKey(const Key('nav_item_skills')));
      await tester.pumpAndSettle();
      expect(find.text('Skills Hub'), findsOneWidget);

      // Switch to Tab 4: Memory Vault
      await tester.tap(find.byKey(const Key('nav_item_vault')));
      await tester.pumpAndSettle();
      expect(find.text('Memory Vault'), findsOneWidget);

      // Enter search query in Memory Vault
      await tester.enterText(find.byKey(const Key('memory_search_input')), 'router');
      await tester.pumpAndSettle();
      expect(find.textContaining('9router'), findsOneWidget);

      // Switch back to Tab 1: Chat
      await tester.tap(find.byKey(const Key('nav_item_chat')));
      await tester.pumpAndSettle();

      // Verify chat input is 100% retained!
      final inputFieldAfter = tester.widget<TextField>(find.byKey(const Key('chat_input_field')));
      expect(inputFieldAfter.controller?.text, testPrompt);

      // Switch back to Tab 4: Memory Vault
      await tester.tap(find.byKey(const Key('nav_item_vault')));
      await tester.pumpAndSettle();

      // Verify memory vault search input is 100% retained!
      final vaultSearchField = tester.widget<TextField>(find.byKey(const Key('memory_search_input')));
      expect(vaultSearchField.controller?.text, 'router');
    });

    testWidgets('preserves skills category filter selection when switching tabs', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Go to Skills Hub
      await tester.tap(find.byKey(const Key('nav_item_skills')));
      await tester.pumpAndSettle();

      // Select 'Device' filter
      await tester.tap(find.byKey(const Key('skills_filter_pill_device')));
      await tester.pumpAndSettle();
      expect(find.text('location_context'), findsOneWidget);
      expect(find.text('camera_vision'), findsNothing);

      // Switch to Tab 3: Pocket Node
      await tester.tap(find.byKey(const Key('nav_item_node')));
      await tester.pumpAndSettle();
      expect(find.text('Pocket Node'), findsOneWidget);

      // Switch back to Tab 2: Skills Hub
      await tester.tap(find.byKey(const Key('nav_item_skills')));
      await tester.pumpAndSettle();

      // Verify filter remains active and filtered state is preserved!
      expect(find.text('location_context'), findsOneWidget);
      expect(find.text('camera_vision'), findsNothing);
    });
  });
}
