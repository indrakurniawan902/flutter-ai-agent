import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockLlmRepository mockLlmRepository;
  late ToolRegistry toolRegistry;
  late AgentCubit cubit;

  const baseUrl = 'https://api.openai.com/v1';
  const model = 'gpt-4o';
  const apiKey = 'test-key';

  setUp(() {
    mockLlmRepository = MockLlmRepository();
    toolRegistry = ToolRegistry();
    cubit = AgentCubit(
      llmRepository: mockLlmRepository,
      toolRegistry: toolRegistry,
      baseUrl: baseUrl,
      model: model,
      apiKey: apiKey,
    );
  });

  tearDown(() {
    cubit.close();
  });

  void registerCountingTool(
    String name,
    Map<String, int> counts,
    List<String> order,
  ) {
    counts[name] = 0;
    toolRegistry.register(
      RegisteredTool(
        name: name,
        description: 'Counting tool $name',
        parameters: const {'type': 'object'},
        securityTier: SecurityTier.tier1Auto,
        execute: (args) async {
          counts[name] = (counts[name] ?? 0) + 1;
          order.add(name);
          return Right('{"result": "$name"}');
        },
      ),
    );
  }

  void stubStream({
    required List<ChatChunk> turn1,
    List<ChatChunk> turn2 = const [],
  }) {
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
        return Right(Stream.fromIterable(turn1));
      }
      return Right(Stream.fromIterable(turn2));
    });
  }

  test(
      'fenced json tool call in assistant text is executed and stripped from the assistant message',
      () async {
    final counts = <String, int>{};
    final order = <String>[];
    registerCountingTool('get_battery', counts, order);

    stubStream(
      turn1: const [
        ChatChunk(
          contentDelta:
              'Let me check.\n\n```json\n{"name": "get_battery", "arguments": {}}\n``` ',
          finishReason: 'stop',
        ),
      ],
      turn2: const [
        ChatChunk(contentDelta: 'Battery is 85%.', finishReason: 'stop'),
      ],
    );

    await cubit.sendMessage('How is my battery?');

    expect(counts['get_battery'], equals(1));
    expect(cubit.state, isA<AgentSuccess>());
    expect(
      (cubit.state as AgentSuccess).response,
      equals('Battery is 85%.'),
    );

    final assistantToolMessage = cubit.messages[1];
    expect(assistantToolMessage.role, equals('assistant'));
    expect(assistantToolMessage.content, equals('Let me check.'));
    expect(assistantToolMessage.toolCalls, isNotNull);
    expect(assistantToolMessage.toolCalls!.first.name, equals('get_battery'));
    expect(assistantToolMessage.content, isNot(contains('```')));
    expect(assistantToolMessage.content, isNot(contains('"name"')));
  });

  test('fenced tool_call block is executed', () async {
    final counts = <String, int>{};
    final order = <String>[];
    registerCountingTool('get_battery', counts, order);

    stubStream(
      turn1: const [
        ChatChunk(
          contentDelta:
              'Checking now.\n```tool_call\n{"name": "get_battery", "arguments": {}}\n```',
          finishReason: 'stop',
        ),
      ],
      turn2: const [
        ChatChunk(contentDelta: 'Battery is 85%.', finishReason: 'stop'),
      ],
    );

    await cubit.sendMessage('Check battery');

    expect(counts['get_battery'], equals(1));
    expect(cubit.state, isA<AgentSuccess>());
    expect(cubit.messages[1].content, equals('Checking now.'));
  });

  test('bare json tool call embedded in prose is executed', () async {
    final counts = <String, int>{};
    final order = <String>[];
    registerCountingTool('get_battery', counts, order);

    stubStream(
      turn1: const [
        ChatChunk(
          contentDelta:
              'Here: {"name": "get_battery", "arguments": {}} done.',
          finishReason: 'stop',
        ),
      ],
      turn2: const [
        ChatChunk(contentDelta: 'All good.', finishReason: 'stop'),
      ],
    );

    await cubit.sendMessage('Check battery');

    expect(counts['get_battery'], equals(1));
    expect(cubit.state, isA<AgentSuccess>());
    expect((cubit.state as AgentSuccess).response, equals('All good.'));
  });

  test('structured tool call plus a markdown tool-call block executes exactly once',
      () async {
    final counts = <String, int>{};
    final order = <String>[];
    registerCountingTool('get_battery', counts, order);
    registerCountingTool('send_sms', counts, order);

    stubStream(
      turn1: const [
        ChatChunk(
          toolCallDeltas: [
            ToolCallDelta(
              index: 0,
              id: 'call_1',
              name: 'get_battery',
              argumentsFragment: '{}',
            ),
          ],
          contentDelta:
              'Also\n```json\n{"name": "send_sms", "arguments": {}}\n```',
          finishReason: 'tool_calls',
        ),
      ],
      turn2: const [
        ChatChunk(contentDelta: 'Done.', finishReason: 'stop'),
      ],
    );

    await cubit.sendMessage('Do both');

    expect(counts['get_battery'], equals(1));
    expect(counts['send_sms'], equals(0));
    expect(cubit.messages[1].toolCalls!.length, equals(1));
    expect(cubit.messages[1].toolCalls!.first.name, equals('get_battery'));
  });

  test('broken json block is preserved verbatim and nothing is executed',
      () async {
    final counts = <String, int>{};
    final order = <String>[];
    registerCountingTool('get_battery', counts, order);

    stubStream(
      turn1: const [
        ChatChunk(
          contentDelta:
              'Sure:\n```json\n{"name": "get_battery", "arguments": {\n``` ',
          finishReason: 'stop',
        ),
      ],
    );

    await cubit.sendMessage('Check battery');

    expect(counts['get_battery'], equals(0));
    expect(cubit.state, isA<AgentSuccess>());
    expect((cubit.state as AgentSuccess).response, contains('```json'));
  });

  test('json that is not a tool call is left in the rendered text', () async {
    final counts = <String, int>{};
    final order = <String>[];
    registerCountingTool('get_battery', counts, order);

    stubStream(
      turn1: const [
        ChatChunk(
          contentDelta: 'Result: {"battery": 85}',
          finishReason: 'stop',
        ),
      ],
    );

    await cubit.sendMessage('Battery level?');

    expect(counts['get_battery'], equals(0));
    expect(cubit.state, isA<AgentSuccess>());
    expect(
      (cubit.state as AgentSuccess).response,
      equals('Result: {"battery": 85}'),
    );
  });

  test('markdown tool call naming an unregistered tool is ignored and the text is preserved',
      () async {
    final counts = <String, int>{};
    final order = <String>[];
    registerCountingTool('get_battery', counts, order);

    stubStream(
      turn1: const [
        ChatChunk(
          contentDelta:
              'Sure\n```json\n{"name": "ghost_tool", "arguments": {}}\n```',
          finishReason: 'stop',
        ),
      ],
    );

    await cubit.sendMessage('Do something');

    expect(counts['get_battery'], equals(0));
    expect(order, isEmpty);
    expect(cubit.state, isA<AgentSuccess>());
    expect((cubit.state as AgentSuccess).response, contains('```json'));
  });

  test('multiple fenced tool calls execute in document order', () async {
    final counts = <String, int>{};
    final order = <String>[];
    registerCountingTool('get_battery', counts, order);
    registerCountingTool('send_sms', counts, order);

    stubStream(
      turn1: const [
        ChatChunk(
          contentDelta:
              'First\n```json\n{"name": "get_battery", "arguments": {}}\n```\n'
              'Second\n```json\n{"name": "send_sms", "arguments": {}}\n```',
          finishReason: 'stop',
        ),
      ],
      turn2: const [
        ChatChunk(contentDelta: 'Both done.', finishReason: 'stop'),
      ],
    );

    await cubit.sendMessage('Run both');

    expect(counts['get_battery'], equals(1));
    expect(counts['send_sms'], equals(1));
    expect(order, equals(['get_battery', 'send_sms']));
  });

  test('fallback tool calls are persisted as structured tool_calls on the assistant message',
      () async {
    final counts = <String, int>{};
    final order = <String>[];
    registerCountingTool('get_battery', counts, order);

    stubStream(
      turn1: const [
        ChatChunk(
          contentDelta:
              'Let me check.\n```json\n{"name": "get_battery", "arguments": {}}\n```',
          finishReason: 'stop',
        ),
      ],
      turn2: const [
        ChatChunk(contentDelta: 'Battery is 85%.', finishReason: 'stop'),
      ],
    );

    await cubit.sendMessage('How is my battery?');

    expect(cubit.messages[1].toolCalls, isNotNull);
    expect(cubit.messages[1].toolCalls!.first.name, equals('get_battery'));

    final toolMessage = cubit.messages.firstWhere((m) => m.role == 'tool');
    expect(toolMessage.toolCallId, equals('call_0'));
  });

  test('recovered tool call carries an id that matches the tool result tool_call_id',
      () async {
    final counts = <String, int>{};
    final order = <String>[];
    registerCountingTool('get_battery', counts, order);

    stubStream(
      turn1: const [
        ChatChunk(
          contentDelta:
              'Let me check.\n```json\n{"name": "get_battery", "arguments": {}}\n```',
          finishReason: 'stop',
        ),
      ],
      turn2: const [
        ChatChunk(contentDelta: 'Battery is 85%.', finishReason: 'stop'),
      ],
    );

    await cubit.sendMessage('How is my battery?');

    final assistantToolMessage =
        cubit.messages.firstWhere((m) => m.toolCalls != null);
    final wire = assistantToolMessage.toWireJson();

    final wireToolCalls = wire['tool_calls'] as List<dynamic>;
    expect(wireToolCalls, hasLength(1));

    final wireEntry = wireToolCalls.first as Map<String, dynamic>;
    expect(wireEntry.containsKey('id'), isTrue);
    final wireId = wireEntry['id'];
    expect(wireId, isA<String>());
    expect((wireId as String).isNotEmpty, isTrue);

    final toolMessages =
        cubit.messages.where((m) => m.role == 'tool').toList();
    expect(toolMessages, isNotEmpty);
    expect(toolMessages.first.toolCallId, equals(wireId));

    final declaredIds = wireToolCalls
        .map((e) => (e as Map<String, dynamic>)['id'])
        .whereType<String>()
        .toSet();
    final referencedIds = toolMessages
        .map((m) => m.toolCallId)
        .whereType<String>()
        .toSet();
    expect(referencedIds.difference(declaredIds), isEmpty);
  });
}
