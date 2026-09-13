import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

/// Builds a minimal OpenAI tool-map fixture:
/// `{'type': 'function', 'function': {'name': n, 'description': d,
/// 'parameters': {}}}`.
Map<String, dynamic> toolMap(String name, String description) => {
      'type': 'function',
      'function': {
        'name': name,
        'description': description,
        'parameters': <String, dynamic>{},
      },
    };

/// Extracts the function names from a captured `tools:` invocation argument.
List<String> toolNames(List<Map<String, dynamic>>? tools) => (tools ?? [])
    .map((def) => def['function']?['name'])
    .whereType<String>()
    .toList();

void main() {
  late MockLlmRepository mockLlmRepository;
  late MockToolPruningService mockToolPruningService;
  late MockSecureStorageService mockSecureStorageService;
  late ToolRegistry toolRegistry;
  late AgentCubit cubit;

  const baseUrl = 'https://api.openai.com/v1';
  const model = 'gpt-4o';
  const apiKey = 'test-key';

  setUpAll(() {
    registerFallbackValue(<Map<String, dynamic>>[]);
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockLlmRepository = MockLlmRepository();
    mockToolPruningService = MockToolPruningService();
    mockSecureStorageService = MockSecureStorageService();
    toolRegistry = ToolRegistry();
    cubit = AgentCubit(
      llmRepository: mockLlmRepository,
      toolRegistry: toolRegistry,
      toolPruningService: mockToolPruningService,
      secureStorageService: mockSecureStorageService,
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
    );
  });

  tearDown(() async {
    await cubit.close();
  });

  group('AgentCubit pruning wiring', () {
    test('refreshSettings loads progressiveToolPruning false from secure storage',
        () async {
      when(() => mockSecureStorageService.getSettings()).thenAnswer(
        (_) async => const SettingsData(progressiveToolPruning: false),
      );

      await cubit.refreshSettings();

      expect(cubit.progressiveToolPruning, isFalse);
    });

    test('refreshSettings loads progressiveToolPruning true from secure storage',
        () async {
      when(() => mockSecureStorageService.getSettings()).thenAnswer(
        (_) async => const SettingsData(progressiveToolPruning: true),
      );

      await cubit.refreshSettings();

      expect(cubit.progressiveToolPruning, isTrue);
    });

    test('refreshSettings keeps default true when the stored flag is null',
        () async {
      when(() => mockSecureStorageService.getSettings()).thenAnswer(
        (_) async => const SettingsData(),
      );

      await cubit.refreshSettings();

      expect(cubit.progressiveToolPruning, isTrue);
    });

    test('sendMessage invokes prune with the last user message and current flag',
        () async {
      toolRegistry.register(
        RegisteredTool(
          name: 'device_status',
          description: 'Get device status',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier1Auto,
          execute: (args) async => const Right('{"status":"ok"}'),
        ),
      );

      when(() => mockToolPruningService.prune(
            prompt: any(named: 'prompt'),
            fullToolDefinitions: any(named: 'fullToolDefinitions'),
            enabled: any(named: 'enabled'),
          )).thenAnswer((invocation) => invocation
              .namedArguments[#fullToolDefinitions] as List<Map<String, dynamic>>);

      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
            temperature: any(named: 'temperature'),
          )).thenAnswer((_) async => Right(Stream.fromIterable([
                const ChatChunk(contentDelta: 'ok', finishReason: 'stop'),
              ])));

      await cubit.sendMessage('what is my battery?');

      final captured = verify(() => mockToolPruningService.prune(
            prompt: captureAny(named: 'prompt'),
            fullToolDefinitions: any(named: 'fullToolDefinitions'),
            enabled: captureAny(named: 'enabled'),
          )).captured;

      expect(captured.length, equals(2));
      expect(captured[0], equals('what is my battery?'));
      expect(captured[1], equals(cubit.progressiveToolPruning));
      expect(cubit.progressiveToolPruning, isTrue);
    });

    test('LLM receives the pruned toolDefs returned by prune', () async {
      toolRegistry.register(
        RegisteredTool(
          name: 'device_status',
          description: 'Get device status',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier1Auto,
          execute: (args) async => const Right('{"status":"ok"}'),
        ),
      );

      final prunedSubset = <Map<String, dynamic>>[
        toolMap('tool_search', 'Searches the available tools by keyword.'),
        toolMap('device_status', 'Get device status'),
      ];
      when(() => mockToolPruningService.prune(
            prompt: any(named: 'prompt'),
            fullToolDefinitions: any(named: 'fullToolDefinitions'),
            enabled: any(named: 'enabled'),
          )).thenReturn(prunedSubset);

      List<Map<String, dynamic>>? capturedTools;
      when(() => mockLlmRepository.streamCompletion(
            baseUrl: any(named: 'baseUrl'),
            model: any(named: 'model'),
            messages: any(named: 'messages'),
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
            temperature: any(named: 'temperature'),
          )).thenAnswer((invocation) async {
        capturedTools ??=
            invocation.namedArguments[#tools] as List<Map<String, dynamic>>?;
        return Right(Stream.fromIterable([
          const ChatChunk(contentDelta: 'ok', finishReason: 'stop'),
        ]));
      });

      await cubit.sendMessage('what is my battery?');

      expect(capturedTools, isNotNull);
      expect(
        toolNames(capturedTools),
        containsAll(<String>['tool_search', 'device_status']),
      );
      expect(toolNames(capturedTools).length, equals(2));
    });
  });

  group('AgentCubit mid-loop tool discovery augmentation', () {
    /// Simulates a meta-only pruning collapse: everything except
    /// tool_search/tool_describe is dropped from the passed definitions.
    List<Map<String, dynamic>> metaOnlyPrune(
      List<Map<String, dynamic>> full,
    ) =>
        full.where((def) {
          final name = def['function']?['name'];
          return name == 'tool_search' || name == 'tool_describe';
        }).toList();

    void registerCalendarTool() {
      toolRegistry.register(
        RegisteredTool(
          name: 'calendar_list_events',
          description: 'List calendar events',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier1Auto,
          execute: (args) async => const Right('[]'),
        ),
      );
    }

    test('tools discovered via tool_search mid-loop are augmented into next turn tool list',
        () async {
      registerCalendarTool();

      when(() => mockToolPruningService.prune(
            prompt: any(named: 'prompt'),
            fullToolDefinitions: any(named: 'fullToolDefinitions'),
            enabled: any(named: 'enabled'),
          )).thenAnswer((invocation) => metaOnlyPrune(invocation
              .namedArguments[#fullToolDefinitions] as List<Map<String, dynamic>>));

      final toolsPerCall = <List<String>>[];
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
        toolsPerCall.add(
          toolNames(invocation.namedArguments[#tools] as List<Map<String, dynamic>>?),
        );

        final hasToolResult =
            messages.any((m) => m['role'] == 'tool');

        // Turn 1: only the user message -> search for calendar tools.
        if (!hasToolResult) {
          return Right(Stream.fromIterable([
            const ChatChunk(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call_search',
                  name: 'tool_search',
                  argumentsFragment: '{"query":"calendar"}',
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ]));
        }

        // Turn 2: search result present, calendar tool not yet executed.
        final calendarCalled = messages.any((m) =>
            m['role'] == 'tool' && m['name'] == 'calendar_list_events');
        if (!calendarCalled) {
          return Right(Stream.fromIterable([
            const ChatChunk(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call_calendar',
                  name: 'calendar_list_events',
                  argumentsFragment: '{}',
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ]));
        }

        // Turn 3: final answer.
        return Right(Stream.fromIterable([
          const ChatChunk(contentDelta: 'done', finishReason: 'stop'),
        ]));
      });

      await cubit.sendMessage('any events?');

      expect(cubit.state, isA<AgentSuccess>());
      expect(cubit.messages.any((m) =>
          m.role == 'tool' && m.name == 'calendar_list_events'), isTrue);
      expect(toolsPerCall.length, greaterThanOrEqualTo(3));

      // Turn 1: meta-only collapse -> calendar tool not offered yet.
      expect(toolsPerCall[0], isNot(contains('calendar_list_events')));
      expect(toolsPerCall[0], contains('tool_search'));

      // Turn 2: discovered tool is augmented alongside the meta-tools.
      expect(toolsPerCall[1], contains('calendar_list_events'));
      expect(toolsPerCall[1], contains('tool_search'));
      expect(toolsPerCall[1], contains('tool_describe'));
    });

    test('discovered tools are not duplicated and are dropped on a fresh send',
        () async {
      registerCalendarTool();

      final promptsSeen = <String>[];
      final firstRunTools = <List<String>>[];
      final secondRunTools = <List<String>>[];

      var runIndex = 0;
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
        final names =
            toolNames(invocation.namedArguments[#tools] as List<Map<String, dynamic>>?);
        if (runIndex == 0) {
          firstRunTools.add(names);
        } else {
          secondRunTools.add(names);
        }

        final lastUser = messages
            .lastWhere((m) => m['role'] == 'user')['content']
            .toString();
        if (lastUser == 'hi') {
          // Second run: finish immediately on the first LLM call.
          return Right(Stream.fromIterable([
            const ChatChunk(contentDelta: 'hello', finishReason: 'stop'),
          ]));
        }

        final hasToolResult = messages.any((m) => m['role'] == 'tool');
        if (!hasToolResult) {
          return Right(Stream.fromIterable([
            const ChatChunk(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call_search',
                  name: 'tool_search',
                  argumentsFragment: '{"query":"calendar"}',
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ]));
        }

        final calendarCalled = messages.any((m) =>
            m['role'] == 'tool' && m['name'] == 'calendar_list_events');
        if (!calendarCalled) {
          return Right(Stream.fromIterable([
            const ChatChunk(
              toolCallDeltas: [
                ToolCallDelta(
                  index: 0,
                  id: 'call_calendar',
                  name: 'calendar_list_events',
                  argumentsFragment: '{}',
                ),
              ],
              finishReason: 'tool_calls',
            ),
          ]));
        }

        return Right(Stream.fromIterable([
          const ChatChunk(contentDelta: 'done', finishReason: 'stop'),
        ]));
      });

      when(() => mockToolPruningService.prune(
            prompt: captureAny(named: 'prompt'),
            fullToolDefinitions: any(named: 'fullToolDefinitions'),
            enabled: any(named: 'enabled'),
          )).thenAnswer((invocation) {
        promptsSeen
            .add('${invocation.namedArguments[#prompt]}');
        return metaOnlyPrune(invocation.namedArguments[#fullToolDefinitions]
            as List<Map<String, dynamic>>);
      });

      await cubit.sendMessage('any events?');
      expect(cubit.state, isA<AgentSuccess>());

      // Calendar tool was discovered during run 1 and augmented on every
      // subsequent LLM turn of the same run (turns 2 and 3), exactly once each.
      final augmentedTurns =
          firstRunTools.where((t) => t.contains('calendar_list_events')).toList();
      expect(augmentedTurns.length, equals(2));
      for (final turn in augmentedTurns) {
        expect(
          turn.where((n) => n == 'calendar_list_events').length,
          equals(1),
          reason: 'discovered tool must not be duplicated within a turn',
        );
      }

      // Fresh send: discovered set is cleared.
      runIndex = 1;
      await cubit.sendMessage('hi');
      expect(cubit.state, isA<AgentSuccess>());

      expect(secondRunTools, isNotEmpty);
      expect(secondRunTools.first, isNot(contains('calendar_list_events')));
      expect(promptsSeen, contains('any events?'));
      expect(promptsSeen, contains('hi'));
    });
  });
}
