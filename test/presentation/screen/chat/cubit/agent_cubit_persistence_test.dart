import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockLlmRepository mockLlmRepository;
  late MockChatLocalRepository mockChatLocalRepository;

  setUpAll(() {
    registerFallbackValue(const ChatMessage(role: 'user'));
    registerFallbackValue(<ChatMessage>[]);
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    mockLlmRepository = MockLlmRepository();
    mockChatLocalRepository = MockChatLocalRepository();
    when(
      () => mockChatLocalRepository.saveMessages(
        any<String>(),
        any<List<ChatMessage>>(),
      ),
    ).thenAnswer(
      (_) async => const Right<Failure, void>(null),
    );
    when(() => mockChatLocalRepository.clearMessages(any<String>()))
        .thenAnswer(
      (_) async => const Right<Failure, void>(null),
    );
    when(() => mockChatLocalRepository.getMessages(any<String>())).thenAnswer(
      (_) async => const Right<Failure, List<ChatMessage>>(<ChatMessage>[]),
    );
  });

  AgentCubit buildCubit({String activeProfileId = 'default'}) {
    return AgentCubit(
      llmRepository: mockLlmRepository,
      toolRegistry: ToolRegistry(),
      chatLocalRepository: mockChatLocalRepository,
      activeProfileId: activeProfileId,
    );
  }

  group('AgentCubit persistence defaults', () {
    test('activeProfileId defaults to default', () {
      final cubit = AgentCubit(
        llmRepository: mockLlmRepository,
        toolRegistry: ToolRegistry(),
      );
      expect(cubit.activeProfileId, 'default');
      cubit.close();
    });

    test('AgentCubit.create accepts optional chatLocalRepository', () {
      final cubit = AgentCubit.create(
        llmRepository: mockLlmRepository,
        chatLocalRepository: mockChatLocalRepository,
      );
      expect(cubit.activeProfileId, 'default');
      cubit.close();
    });
  });

  group('addMessage', () {
    test('appends message, persists, emits AgentIdle', () async {
      final cubit = buildCubit();
      cubit.addMessage(const ChatMessage(role: 'user', content: 'Hi'));

      await untilCalled(
        () => mockChatLocalRepository.saveMessages(
          any<String>(),
          any<List<ChatMessage>>(),
        ),
      );

      expect(cubit.messages.length, 1);
      expect(cubit.messages.first.content, 'Hi');
      expect(cubit.state, isA<AgentIdle>());
      verify(
        () => mockChatLocalRepository.saveMessages(
          'default',
          any<List<ChatMessage>>(),
        ),
      ).called(1);
      await cubit.close();
    });
  });

  group('loadChatHistory', () {
    test('loads messages, replaces history, emits AgentIdle', () async {
      final stored = [
        const ChatMessage(role: 'user', content: 'Hello'),
        const ChatMessage(role: 'assistant', content: 'Hi'),
      ];
      when(() => mockChatLocalRepository.getMessages('default'))
          .thenAnswer((_) async => Right<Failure, List<ChatMessage>>(stored));

      final cubit = buildCubit();
      await cubit.loadChatHistory();

      expect(cubit.messages.length, 2);
      expect(cubit.messages[0].content, 'Hello');
      expect(cubit.state, isA<AgentIdle>());
      final idle = cubit.state as AgentIdle;
      expect(idle.messages.length, 2);
      await cubit.close();
    });

    test('profileId param updates activeProfileId', () async {
      when(() => mockChatLocalRepository.getMessages('p2')).thenAnswer(
        (_) async => const Right<Failure, List<ChatMessage>>(<ChatMessage>[
          ChatMessage(role: 'user', content: 'from p2'),
        ]),
      );

      final cubit = buildCubit();
      await cubit.loadChatHistory('p2');

      expect(cubit.activeProfileId, 'p2');
      expect(cubit.messages.length, 1);
      expect(cubit.messages.first.content, 'from p2');
      await cubit.close();
    });
  });

  group('switchProfile', () {
    test('sets activeProfileId and loads history', () async {
      when(() => mockChatLocalRepository.getMessages('work')).thenAnswer(
        (_) async => const Right<Failure, List<ChatMessage>>(<ChatMessage>[
          ChatMessage(role: 'user', content: 'work msg'),
        ]),
      );

      final cubit = buildCubit(activeProfileId: 'default');
      await cubit.switchProfile('work');

      expect(cubit.activeProfileId, 'work');
      expect(cubit.messages.length, 1);
      expect(cubit.messages.first.content, 'work msg');
      verify(() => mockChatLocalRepository.getMessages('work')).called(1);
      await cubit.close();
    });
  });

  group('reset (/new)', () {
    test('clears messages and calls clearMessages', () async {
      final cubit = buildCubit();
      cubit.addMessage(const ChatMessage(role: 'user', content: 'Hi'));
      await untilCalled(
        () => mockChatLocalRepository.saveMessages(
          any<String>(),
          any<List<ChatMessage>>(),
        ),
      );
      expect(cubit.messages, isNotEmpty);

      cubit.reset();
      await untilCalled(
        () => mockChatLocalRepository.clearMessages(any<String>()),
      );

      expect(cubit.messages, isEmpty);
      expect(cubit.state, isA<AgentIdle>());
      verify(() => mockChatLocalRepository.clearMessages('default')).called(1);
      await cubit.close();
    });

    test('reset scopes clear to activeProfileId', () async {
      final cubit = buildCubit(activeProfileId: 'p9');
      cubit.reset();
      await untilCalled(
        () => mockChatLocalRepository.clearMessages(any<String>()),
      );
      verify(() => mockChatLocalRepository.clearMessages('p9')).called(1);
      await cubit.close();
    });
  });

  group('ReAct loop persistence', () {
    test('sendMessage persists history for activeProfileId', () async {
      when(
        () => mockLlmRepository.streamCompletion(
          baseUrl: any(named: 'baseUrl'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          apiKey: any(named: 'apiKey'),
        ),
      ).thenAnswer(
        (_) async => Right<Failure, Stream<ChatChunk>>(
          Stream.fromIterable([
            const ChatChunk(contentDelta: 'Hello back', finishReason: 'stop'),
          ]),
        ),
      );

      final cubit = buildCubit(activeProfileId: 'default');
      await cubit.sendMessage('Hello');

      expect(cubit.state, isA<AgentSuccess>());
      expect(cubit.messages.length, 2);
      verify(
        () => mockChatLocalRepository.saveMessages(
          'default',
          any<List<ChatMessage>>(),
        ),
      ).called(greaterThanOrEqualTo(1));
      await cubit.close();
    });

    test('tool execution persists history', () async {
      final registry = ToolRegistry();
      when(
        () => mockLlmRepository.streamCompletion(
          baseUrl: any(named: 'baseUrl'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          apiKey: any(named: 'apiKey'),
        ),
      ).thenAnswer(
        (_) async => Right<Failure, Stream<ChatChunk>>(
          Stream.fromIterable([
            const ChatChunk(
              contentDelta: '<thought>plan</thought>Done',
              finishReason: 'stop',
            ),
          ]),
        ),
      );

      final cubit = AgentCubit(
        llmRepository: mockLlmRepository,
        toolRegistry: registry,
        chatLocalRepository: mockChatLocalRepository,
      );
      await cubit.sendMessage('Hi');

      final assistant =
          cubit.messages.lastWhere((m) => m.role == 'assistant');
      expect(assistant.thoughtProcess, 'plan');
      verify(
        () => mockChatLocalRepository.saveMessages(
          'default',
          any<List<ChatMessage>>(),
        ),
      ).called(greaterThanOrEqualTo(1));
      await cubit.close();
    });
  });
}
