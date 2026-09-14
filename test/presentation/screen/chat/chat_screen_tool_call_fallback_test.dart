import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_routes.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockLlmRepository mockLlmRepository;
  late MockSettingsCubit mockSettingsCubit;
  late ToolRegistry toolRegistry;

  setUp(() async {
    await sl.reset();
    mockLlmRepository = MockLlmRepository();
    mockSettingsCubit = MockSettingsCubit();
    toolRegistry = ToolRegistry();

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsLoaded(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o',
        temperature: 0.7,
      ),
    );
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream.empty());

    sl.registerFactory<SettingsCubit>(() => mockSettingsCubit);
  });

  tearDown(() async {
    await sl.reset();
  });

  void registerBatteryTool(void Function() onExecute) {
    toolRegistry.register(
      RegisteredTool(
        name: 'get_battery',
        description: 'Get device battery',
        parameters: const {'type': 'object'},
        securityTier: SecurityTier.tier1Auto,
        execute: (args) async {
          onExecute();
          return const Right('{"battery": 85}');
        },
      ),
    );
  }

  AgentCubit buildCubit() {
    final cubit = AgentCubit(
      llmRepository: mockLlmRepository,
      toolRegistry: toolRegistry,
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o',
      apiKey: 'test-key',
    );
    sl.registerFactory<AgentCubit>(() => cubit);
    return cubit;
  }

  void stubSingleTurn(String content) {
    when(() => mockLlmRepository.streamCompletion(
          baseUrl: any(named: 'baseUrl'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          apiKey: any(named: 'apiKey'),
          temperature: any(named: 'temperature'),
        )).thenAnswer((_) async => Right(Stream.fromIterable([
              ChatChunk(contentDelta: content),
            ])));
  }

  void stubTwoTurns(String firstTurn, String secondTurn) {
    when(() => mockLlmRepository.streamCompletion(
          baseUrl: any(named: 'baseUrl'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          apiKey: any(named: 'apiKey'),
          temperature: any(named: 'temperature'),
        )).thenAnswer((invocation) async {
      final messages =
          invocation.namedArguments[#messages] as List<Map<String, dynamic>>;
      if (messages.length == 1) {
        return Right(Stream.fromIterable([
          ChatChunk(contentDelta: firstTurn),
        ]));
      }
      return Right(Stream.fromIterable([
        ChatChunk(contentDelta: secondTurn),
      ]));
    });
  }

  Widget createWidgetUnderTest() {
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          name: AppRoutes.nrChat,
          builder: (context, state) => const ChatScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }

  Future<void> sendPrompt(
    WidgetTester tester,
    String prompt,
    bool Function() ready,
  ) async {
    await tester.enterText(find.byKey(const Key('chat_input_field')), prompt);
    await tester.pump();

    await tester.tap(find.byKey(const Key('chat_send_button')));
    await tester.pump();

    for (var i = 0; i < 300 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pump();
  }

  group('ChatScreen - markdown/JSON tool-call fallback rendering', () {
    testWidgets(
        'recovered markdown tool-call block is executed and never rendered in the bubble',
        (tester) async {
      var executedCount = 0;
      registerBatteryTool(() => executedCount++);
      stubTwoTurns(
        'Let me check.\n\n```json\n{"name": "get_battery", "arguments": {}}\n``` ',
        'Battery is 85%.',
      );

      final cubit = buildCubit();

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await sendPrompt(
        tester,
        'How is my battery?',
        () => cubit.messages.length >= 4,
      );

      expect(executedCount, 1);
      expect(find.textContaining('```'), findsNothing);
      expect(find.textContaining('"name"'), findsNothing);
      expect(find.textContaining('Battery is 85%.'), findsOneWidget);
      expect(find.textContaining('Let me check.'), findsOneWidget);
    });

    testWidgets(
        'truncated markdown tool-call block never executes and is rendered as-is',
        (tester) async {
      var executedCount = 0;
      registerBatteryTool(() => executedCount++);
      stubSingleTurn(
        'Sure:\n```json\n{"name": "get_battery", "arguments": {\n``` ',
      );

      final cubit = buildCubit();

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await sendPrompt(
        tester,
        'Check the battery',
        () => cubit.messages.length >= 2,
      );

      expect(executedCount, 0);
      expect(find.textContaining('"name"'), findsOneWidget);
    });

    testWidgets(
        'non-tool JSON blob is rendered as-is and executes nothing',
        (tester) async {
      var executedCount = 0;
      registerBatteryTool(() => executedCount++);
      stubSingleTurn('Result: {"battery": 85}');

      final cubit = buildCubit();

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await sendPrompt(
        tester,
        'Show raw result',
        () => cubit.messages.length >= 2,
      );

      expect(executedCount, 0);
      expect(find.textContaining('{"battery": 85}'), findsOneWidget);
    });
  });
}
