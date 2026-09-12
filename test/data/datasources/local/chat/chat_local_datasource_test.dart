import 'dart:convert';

import 'package:flutter_ai_agent/data/datasources/local/chat/chat_local_datasource.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockFlutterSecureStorage mockStorage;
  late ChatLocalDatasourceImpl datasource;

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    datasource = ChatLocalDatasourceImpl(storage: mockStorage);
  });

  group('ChatLocalDatasource key', () {
    test('keyFor uses chat_history_\$profileId', () {
      expect(
        ChatLocalDatasourceImpl.keyFor('abc'),
        'chat_history_abc',
      );
    });
  });

  group('getMessages', () {
    test('returns empty list when storage returns null', () async {
      when(() => mockStorage.read(key: 'chat_history_p1'))
          .thenAnswer((_) async => null);

      final result = await datasource.getMessages('p1');

      expect(result, isEmpty);
    });

    test('returns empty list when storage returns empty string', () async {
      when(() => mockStorage.read(key: 'chat_history_p1'))
          .thenAnswer((_) async => '  ');

      final result = await datasource.getMessages('p1');

      expect(result, isEmpty);
    });

    test('returns empty list on corrupt JSON', () async {
      when(() => mockStorage.read(key: 'chat_history_p1'))
          .thenAnswer((_) async => '{not valid');

      final result = await datasource.getMessages('p1');

      expect(result, isEmpty);
    });

    test('returns parsed messages on valid JSON', () async {
      final messages = [
        const ChatMessage(role: 'user', content: 'Hello'),
        const ChatMessage(
          role: 'assistant',
          content: 'Hi there',
          thoughtProcess: 'thinking',
        ),
      ];
      final raw = jsonEncode(messages.map((m) => m.toJson()).toList());
      when(() => mockStorage.read(key: 'chat_history_p1'))
          .thenAnswer((_) async => raw);

      final result = await datasource.getMessages('p1');

      expect(result.length, 2);
      expect(result[0].role, 'user');
      expect(result[0].content, 'Hello');
      expect(result[1].role, 'assistant');
      expect(result[1].thoughtProcess, 'thinking');
    });

    test('scopes keys per profile', () async {
      when(() => mockStorage.read(key: 'chat_history_a'))
          .thenAnswer((_) async => null);
      when(() => mockStorage.read(key: 'chat_history_b'))
          .thenAnswer((_) async => null);

      await datasource.getMessages('a');
      await datasource.getMessages('b');

      verify(() => mockStorage.read(key: 'chat_history_a')).called(1);
      verify(() => mockStorage.read(key: 'chat_history_b')).called(1);
    });
  });

  group('saveMessages', () {
    test('writes json with profile-scoped key', () async {
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      final messages = [
        const ChatMessage(role: 'user', content: 'Hello'),
      ];
      await datasource.saveMessages('p1', messages);

      final captured = verify(() => mockStorage.write(
            key: captureAny(named: 'key'),
            value: captureAny(named: 'value'),
          )).captured;
      expect(captured[0], 'chat_history_p1');
      final decoded = jsonDecode(captured[1] as String) as List;
      expect(decoded.length, 1);
      expect((decoded.first as Map)['role'], 'user');
    });

    test('persists thought_process field', () async {
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      await datasource.saveMessages('p1', const [
        ChatMessage(role: 'assistant', content: 'Hi', thoughtProcess: 'plan'),
      ]);

      final captured = verify(() => mockStorage.write(
            key: any(named: 'key'),
            value: captureAny(named: 'value'),
          )).captured;
      final decoded =
          jsonDecode(captured.first as String) as List;
      final first = decoded.first as Map<String, dynamic>;
      expect(first['thought_process'], 'plan');
    });
  });

  group('clearMessages', () {
    test('deletes profile-scoped key', () async {
      when(() => mockStorage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});

      await datasource.clearMessages('p1');

      verify(() => mockStorage.delete(key: 'chat_history_p1')).called(1);
    });
  });

  group('roundtrip', () {
    test('save then get preserves messages', () async {
      String? stored;
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((inv) async {
        stored = inv.namedArguments[#value] as String?;
      });
      when(() => mockStorage.read(key: any(named: 'key')))
          .thenAnswer((_) async => stored);

      final messages = [
        const ChatMessage(role: 'user', content: 'Hello'),
        const ChatMessage(
          role: 'assistant',
          content: 'World',
          thoughtProcess: 'reasoning',
        ),
      ];
      await datasource.saveMessages('p1', messages);
      final loaded = await datasource.getMessages('p1');

      expect(loaded.length, 2);
      expect(loaded[1].thoughtProcess, 'reasoning');
    });
  });
}
