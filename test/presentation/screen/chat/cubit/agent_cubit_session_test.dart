import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/session.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockLlmRepository mockLlmRepository;
  late MockChatLocalRepository repo;

  const profileId = 'p1';

  Session session(int id, {String title = 'New chat', int updatedAt = 0}) {
    return Session(
      id: id,
      profileId: profileId,
      title: title,
      createdAt: 0,
      updatedAt: updatedAt,
    );
  }

  ChatMessage msg(String role, String content) =>
      ChatMessage(role: role, content: content);

  setUpAll(() {
    registerFallbackValue(const ChatMessage(role: 'user'));
    registerFallbackValue(<ChatMessage>[]);
  });

  setUp(() {
    mockLlmRepository = MockLlmRepository();
    repo = MockChatLocalRepository();
    when(() => repo.getSessions(any<String>()))
        .thenAnswer((_) async => const Right<Failure, List<Session>>([]));
    when(() => repo.getMessages(any<String>())).thenAnswer(
      (_) async => const Right<Failure, List<ChatMessage>>(<ChatMessage>[]),
    );
    when(() => repo.saveMessages(any<String>(), any<List<ChatMessage>>()))
        .thenAnswer((_) async => const Right<Failure, void>(null));
    when(() => repo.clearMessages(any<String>()))
        .thenAnswer((_) async => const Right<Failure, void>(null));
    when(() => repo.createSession(any<String>(), any<String?>()))
        .thenAnswer((_) async => Right<Failure, Session>(session(50)));
    when(() => repo.updateSessionTitle(any<int>(), any<String>()))
        .thenAnswer((_) async => const Right<Failure, void>(null));
    when(() => repo.deleteSession(any<int>()))
        .thenAnswer((_) async => const Right<Failure, void>(null));
  });

  AgentCubit buildCubit({String activeProfileId = profileId}) {
    return AgentCubit(
      llmRepository: mockLlmRepository,
      toolRegistry: ToolRegistry(),
      chatLocalRepository: repo,
      activeProfileId: activeProfileId,
    );
  }

  void stubFinalStream(String text) {
    when(
      () => mockLlmRepository.streamCompletion(
        baseUrl: any(named: 'baseUrl'),
        model: any(named: 'model'),
        messages: any(named: 'messages'),
        tools: any(named: 'tools'),
        apiKey: any(named: 'apiKey'),
        temperature: any(named: 'temperature'),
      ),
    ).thenAnswer(
      (_) async => Right<Failure, Stream<ChatChunk>>(
        Stream.fromIterable([
          ChatChunk(contentDelta: text, finishReason: 'stop'),
        ]),
      ),
    );
  }

  group('session bootstrap', () {
    test('switchProfile with zero sessions creates a default session',
        () async {
      final cubit = buildCubit();
      await cubit.switchProfile(profileId);

      expect(cubit.activeSessionId, 50);
      verify(() => repo.createSession(profileId, any<String?>())).called(1);
      await cubit.close();
    });

    test('legacy profile-keyed thread migrates into a titled session',
        () async {
      final legacy = [msg('user', 'Migrate me'), msg('assistant', 'ok')];
      when(() => repo.getMessages(profileId)).thenAnswer(
        (_) async => Right<Failure, List<ChatMessage>>(legacy),
      );
      when(() => repo.getMessages('42')).thenAnswer(
        (_) async => Right<Failure, List<ChatMessage>>(legacy),
      );
      when(() => repo.createSession(any<String>(), any<String?>()))
          .thenAnswer((_) async => Right<Failure, Session>(session(42)));

      final cubit = buildCubit();
      await cubit.switchProfile(profileId);

      expect(cubit.activeSessionId, 42);
      expect(cubit.messages.length, 2);
      verify(() => repo.createSession(profileId, 'Migrate me')).called(1);
      verify(
        () => repo.saveMessages(
          '42',
          any<List<ChatMessage>>(),
        ),
      ).called(1);
      verify(() => repo.clearMessages(profileId)).called(1);
      await cubit.close();
    });

    test('getSessions failure falls back to profile-keyed persistence',
        () async {
      when(() => repo.getSessions(any<String>())).thenThrow(
        Exception('boom'),
      );
      final cubit = buildCubit();
      await cubit.loadChatHistory();

      expect(cubit.activeSessionId, isNull);
      cubit.addMessage(const ChatMessage(role: 'user', content: 'x'));
      await untilCalled(
        () => repo.saveMessages(any<String>(), any<List<ChatMessage>>()),
      );
      verify(
        () => repo.saveMessages(profileId, any<List<ChatMessage>>()),
      ).called(greaterThanOrEqualTo(1));
      await cubit.close();
    });

    test('sendMessage bootstraps a session when none is active', () async {
      stubFinalStream('ok');

      final cubit = buildCubit();
      await cubit.sendMessage('hello');

      expect(cubit.activeSessionId, 50);
      verify(() => repo.createSession(profileId, any<String?>())).called(1);
      await untilCalled(
        () => repo.saveMessages('50', any<List<ChatMessage>>()),
      );
      verify(
        () => repo.saveMessages('50', any<List<ChatMessage>>()),
      ).called(greaterThanOrEqualTo(1));
      await cubit.close();
    });

    test('refreshSessions seeds a session when none is active', () async {
      final cubit = buildCubit();
      await cubit.refreshSessions();

      expect(cubit.activeSessionId, isNotNull);
      expect(cubit.activeSessionId, 50);
      verify(() => repo.createSession(profileId, any<String?>())).called(1);
      await cubit.close();
    });

    test('bootstrap does not lose migrated legacy history', () async {
      final legacy = [msg('user', 'old one'), msg('assistant', 'old two')];
      final store = <String, List<ChatMessage>>{profileId: List.of(legacy)};
      final writesTo50 = <List<ChatMessage>>[];

      when(() => repo.getSessions(any<String>())).thenAnswer(
        (_) async => const Right<Failure, List<Session>>(<Session>[]),
      );
      when(() => repo.getMessages(any<String>())).thenAnswer((inv) async {
        final key = inv.positionalArguments.first as String;
        return Right<Failure, List<ChatMessage>>(List.of(store[key] ?? const []));
      });
      when(() => repo.saveMessages(any<String>(), any<List<ChatMessage>>()))
          .thenAnswer((inv) async {
        final key = inv.positionalArguments.first as String;
        final list = inv.positionalArguments.last as List<ChatMessage>;
        if (key == '50') writesTo50.add(List.of(list));
        store[key] = List.of(list);
        return const Right<Failure, void>(null);
      });
      when(() => repo.clearMessages(any<String>())).thenAnswer((inv) async {
        final key = inv.positionalArguments.first as String;
        store[key] = <ChatMessage>[];
        return const Right<Failure, void>(null);
      });
      // Left ends the ReAct loop before an assistant turn is appended/persisted,
      // so the final saveMessages('50') is exactly the user-message append.
      when(
        () => mockLlmRepository.streamCompletion(
          baseUrl: any(named: 'baseUrl'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          apiKey: any(named: 'apiKey'),
          temperature: any(named: 'temperature'),
        ),
      ).thenAnswer(
        (_) async =>
            Left<Failure, Stream<ChatChunk>>(const ConnectionFailure()),
      );

      final cubit = buildCubit();
      await cubit.sendMessage('new msg');

      expect(writesTo50, isNotEmpty);
      expect(
        writesTo50.last.map((m) => m.content).toList(),
        ['old one', 'old two', 'new msg'],
      );
      expect(
        cubit.messages.map((m) => m.content).toList(),
        ['old one', 'old two', 'new msg'],
      );
      await cubit.close();
    });

    test('drawer-open seeding loads session messages', () async {
      when(() => repo.getSessions(any<String>())).thenAnswer(
        (_) async => Right<Failure, List<Session>>([session(7)]),
      );
      when(() => repo.getMessages('7')).thenAnswer(
        (_) async =>
            Right<Failure, List<ChatMessage>>([msg('user', 'hello')]),
      );

      final cubit = buildCubit();
      await cubit.refreshSessions();

      expect(cubit.messages.length, 1);
      expect(cubit.messages.single.content, 'hello');
      await cubit.close();
    });
  });

  group('newChat', () {
    test('creates session, swaps activeSessionId, emits empty AgentIdle',
        () async {
      final cubit = buildCubit();
      await cubit.newChat();

      verify(() => repo.createSession(profileId, any<String?>())).called(1);
      expect(cubit.activeSessionId, 50);
      expect(cubit.messages, isEmpty);
      expect(cubit.state, isA<AgentIdle>());
      await cubit.close();
    });
  });

  group('switchSession', () {
    test('loads that session messages and replaces history', () async {
      when(() => repo.getMessages('2')).thenAnswer(
        (_) async => Right<Failure, List<ChatMessage>>(
          [msg('user', 'a'), msg('assistant', 'b')],
        ),
      );

      final cubit = buildCubit();
      await cubit.switchSession(2);

      expect(cubit.activeSessionId, 2);
      expect(cubit.messages.length, 2);
      expect(cubit.messages.first.content, 'a');
      verify(() => repo.getMessages('2')).called(1);
      await cubit.close();
    });
  });

  group('deleteSession', () {
    test('active session falls back to newest remaining messages', () async {
      when(() => repo.getSessions(any<String>())).thenAnswer(
        (_) async => Right<Failure, List<Session>>(
          [session(1, updatedAt: 20), session(2, updatedAt: 10)],
        ),
      );
      when(() => repo.getMessages('1')).thenAnswer(
        (_) async => Right<Failure, List<ChatMessage>>([msg('user', 'one')]),
      );
      when(() => repo.getMessages('2')).thenAnswer(
        (_) async => Right<Failure, List<ChatMessage>>([msg('user', 'two')]),
      );

      final cubit = buildCubit();
      await cubit.switchProfile(profileId);
      expect(cubit.activeSessionId, 1);

      await cubit.deleteSession(1);

      expect(cubit.activeSessionId, 2);
      expect(cubit.messages.first.content, 'two');
      verify(() => repo.deleteSession(1)).called(1);
      await cubit.close();
    });

    test('deleting the only session creates a fresh one', () async {
      when(() => repo.getSessions(any<String>())).thenAnswer(
        (_) async => Right<Failure, List<Session>>([session(7)]),
      );
      when(() => repo.createSession(any<String>(), any<String?>()))
          .thenAnswer((_) async => Right<Failure, Session>(session(88)));

      final cubit = buildCubit();
      await cubit.switchProfile(profileId);
      expect(cubit.activeSessionId, 7);

      await cubit.deleteSession(7);

      expect(cubit.activeSessionId, 88);
      expect(cubit.messages, isEmpty);
      verify(() => repo.createSession(profileId, any<String?>())).called(1);
      await cubit.close();
    });
  });

  group('renameSession', () {
    test('updates cached session title', () async {
      when(() => repo.getSessions(any<String>())).thenAnswer(
        (_) async => Right<Failure, List<Session>>(
          [session(1, title: 'New chat'), session(2, title: 'New chat')],
        ),
      );

      final cubit = buildCubit();
      await cubit.switchProfile(profileId);

      await cubit.renameSession(2, 'Renamed');

      verify(() => repo.updateSessionTitle(2, 'Renamed')).called(1);
      final cached = cubit.sessions.firstWhere((s) => s.id == 2);
      expect(cached.title, 'Renamed');
      await cubit.close();
    });
  });

  group('auto-title', () {
    test('sendMessage on a New chat session sets trimmed title', () async {
      when(() => repo.getSessions(any<String>())).thenAnswer(
        (_) async => Right<Failure, List<Session>>([session(5)]),
      );
      stubFinalStream('ok');

      final cubit = buildCubit();
      await cubit.switchProfile(profileId);
      expect(cubit.activeSessionId, 5);

      await cubit.sendMessage('What is the weather?');

      verify(() => repo.updateSessionTitle(5, 'What is the weather?'))
          .called(1);
      expect(cubit.sessions.first.title, 'What is the weather?');
      verifyNever(
        () => repo.createSession(any<String>(), any<String?>()),
      );
      await cubit.close();
    });

    test('long first message truncates title to 40 chars', () async {
      when(() => repo.getSessions(any<String>())).thenAnswer(
        (_) async => Right<Failure, List<Session>>([session(5)]),
      );
      stubFinalStream('ok');

      final cubit = buildCubit();
      await cubit.switchProfile(profileId);

      final long = 'a' * 60;
      await cubit.sendMessage(long);

      final captured = verify(
        () => repo.updateSessionTitle(5, captureAny<String>()),
      ).captured;
      final title = captured.single as String;
      expect(title.length, 40);
      await cubit.close();
    });
  });
}
