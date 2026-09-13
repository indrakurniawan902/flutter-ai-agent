import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/repositories/chat_local_repository_impl.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

void main() {
  late MockChatLocalDatasource mockDatasource;
  late ChatLocalRepositoryImpl repository;

  setUpAll(() {
    registerFallbackValue(<ChatMessage>[]);
  });

  setUp(() {
    mockDatasource = MockChatLocalDatasource();
    repository = ChatLocalRepositoryImpl(datasource: mockDatasource);
  });

  group('titleFromMessage', () {
    test('falls back to default when message is null or blank', () {
      expect(
        ChatLocalRepositoryImpl.titleFromMessage(null),
        ChatLocalRepositoryImpl.untitledSessionTitle,
      );
      expect(
        ChatLocalRepositoryImpl.titleFromMessage('   '),
        ChatLocalRepositoryImpl.untitledSessionTitle,
      );
    });

    test('collapses whitespace and keeps short titles intact', () {
      expect(
        ChatLocalRepositoryImpl.titleFromMessage('  Hello   world  '),
        'Hello world',
      );
    });

    test('truncates long titles to 40 characters', () {
      final long = 'a' * 80;
      final title = ChatLocalRepositoryImpl.titleFromMessage(long);
      expect(title.length, ChatLocalRepositoryImpl.maxTitleLength);
      expect(title, 'a' * 40);
    });
  });

  group('messages', () {
    test('getMessages returns Right on success', () async {
      final messages = [const ChatMessage(role: 'user', content: 'Hi')];
      when(() => mockDatasource.getMessages('s1'))
          .thenAnswer((_) async => messages);

      final result = await repository.getMessages('s1');

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => []), messages);
    });

    test('getMessages returns Left(CacheFailure) on error', () async {
      when(() => mockDatasource.getMessages('s1'))
          .thenThrow(Exception('boom'));

      final result = await repository.getMessages('s1');

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<CacheFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('saveMessages delegates and returns Right', () async {
      final messages = [const ChatMessage(role: 'user', content: 'Hi')];
      when(() => mockDatasource.saveMessages('s1', messages))
          .thenAnswer((_) async {});

      final result = await repository.saveMessages('s1', messages);

      expect(result.isRight(), isTrue);
      verify(() => mockDatasource.saveMessages('s1', messages)).called(1);
    });

    test('saveMessages returns Left(CacheFailure) on error', () async {
      when(() => mockDatasource.saveMessages('s1', any()))
          .thenThrow(Exception('boom'));

      final result = await repository.saveMessages(
        's1',
        [const ChatMessage(role: 'user', content: 'Hi')],
      );

      expect(result.isLeft(), isTrue);
    });

    test('clearMessages delegates and returns Right', () async {
      when(() => mockDatasource.clearMessages('s1'))
          .thenAnswer((_) async {});

      final result = await repository.clearMessages('s1');

      expect(result.isRight(), isTrue);
      verify(() => mockDatasource.clearMessages('s1')).called(1);
    });

    test('clearMessages returns Left(CacheFailure) on error', () async {
      when(() => mockDatasource.clearMessages('s1'))
          .thenThrow(Exception('boom'));

      final result = await repository.clearMessages('s1');

      expect(result.isLeft(), isTrue);
    });
  });

  group('sessions', () {
    final session = const Session(
      id: 1,
      profileId: 'p1',
      title: 'Hello',
      createdAt: 100,
      updatedAt: 100,
    );

    test('getSessions returns Right with sessions', () async {
      when(() => mockDatasource.getSessions('p1'))
          .thenAnswer((_) async => [session]);

      final result = await repository.getSessions('p1');

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => []), [session]);
    });

    test('getSessions returns Left(CacheFailure) on error', () async {
      when(() => mockDatasource.getSessions('p1'))
          .thenThrow(Exception('boom'));

      final result = await repository.getSessions('p1');

      expect(result.isLeft(), isTrue);
    });

    test('createSession persists the provided title', () async {
      when(() => mockDatasource.createSession('p1', 'Hello'))
          .thenAnswer((_) async => session);

      final result = await repository.createSession('p1', 'Hello');

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => session), session);
      verify(() => mockDatasource.createSession('p1', 'Hello')).called(1);
    });

    test('createSession falls back to default title when omitted', () async {
      final fallback = session.copyWith(
        title: ChatLocalRepositoryImpl.untitledSessionTitle,
      );
      when(() => mockDatasource.createSession(
            'p1',
            ChatLocalRepositoryImpl.untitledSessionTitle,
          )).thenAnswer((_) async => fallback);

      final result = await repository.createSession('p1');

      expect(result.isRight(), isTrue);
      expect(
        result.getOrElse(() => session).title,
        ChatLocalRepositoryImpl.untitledSessionTitle,
      );
    });

    test('createSession returns Left(CacheFailure) on error', () async {
      when(() => mockDatasource.createSession('p1', any()))
          .thenThrow(Exception('boom'));

      final result = await repository.createSession('p1', 'Hello');

      expect(result.isLeft(), isTrue);
    });

    test('getSession returns Right(session) when found', () async {
      when(() => mockDatasource.getSession(1))
          .thenAnswer((_) async => session);

      final result = await repository.getSession(1);

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => null), session);
    });

    test('getSession returns Right(null) when missing', () async {
      when(() => mockDatasource.getSession(1)).thenAnswer((_) async => null);

      final result = await repository.getSession(1);

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => session), isNull);
    });

    test('getSession returns Left(CacheFailure) on error', () async {
      when(() => mockDatasource.getSession(1)).thenThrow(Exception('boom'));

      final result = await repository.getSession(1);

      expect(result.isLeft(), isTrue);
    });

    test('updateSessionTitle delegates normalized title', () async {
      when(() => mockDatasource.updateSessionTitle(1, 'New title'))
          .thenAnswer((_) async {});

      final result = await repository.updateSessionTitle(1, '  New   title ');

      expect(result.isRight(), isTrue);
      verify(() => mockDatasource.updateSessionTitle(1, 'New title')).called(1);
    });

    test('updateSessionTitle returns Left(CacheFailure) on error', () async {
      when(() => mockDatasource.updateSessionTitle(1, any()))
          .thenThrow(Exception('boom'));

      final result = await repository.updateSessionTitle(1, 'x');

      expect(result.isLeft(), isTrue);
    });

    test('deleteSession delegates and returns Right', () async {
      when(() => mockDatasource.deleteSession(1)).thenAnswer((_) async {});

      final result = await repository.deleteSession(1);

      expect(result.isRight(), isTrue);
      verify(() => mockDatasource.deleteSession(1)).called(1);
    });

    test('deleteSession returns Left(CacheFailure) on error', () async {
      when(() => mockDatasource.deleteSession(1)).thenThrow(Exception('boom'));

      final result = await repository.deleteSession(1);

      expect(result.isLeft(), isTrue);
    });
  });
}
