import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/common/exception.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/models/chat/chat_remote_response.dart';
import 'package:flutter_ai_agent/data/repositories/chat_repository_impl.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

void main() {
  late MockChatDatasource mockDatasource;
  late LlmRepositoryImpl repository;

  const baseUrl = 'https://api.example.com/v1';
  const model = 'gpt-4';
  final messages = <Map<String, dynamic>>[
    {'role': 'user', 'content': 'Hello'},
  ];

  setUp(() {
    mockDatasource = MockChatDatasource();
    repository = LlmRepositoryImpl(datasource: mockDatasource);
  });

  group('LlmRepositoryImpl.streamCompletion', () {
    test('returns Right with mapped Stream<ChatChunk> on success', () async {
      final remoteChunks = <ChatChunkRemoteResponse>[
        ChatChunkRemoteResponse(
          id: 'c1',
          model: 'gpt-4',
          contentDelta: 'Hi',
        ),
        ChatChunkRemoteResponse(
          id: 'c2',
          model: 'gpt-4',
          contentDelta: '!',
        ),
      ];
      final streamController = StreamController<ChatChunkRemoteResponse>();
      for (final chunk in remoteChunks) {
        streamController.add(chunk);
      }
      streamController.close();

      when(() => mockDatasource.streamCompletion(
            baseUrl: baseUrl,
            model: model,
            messages: messages,
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async => streamController.stream);

      final result = await repository.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
      );

      expect(result.isRight(), isTrue);

      final stream = result.getOrElse(() => const Stream<ChatChunk>.empty());
      final chunks = await stream.toList();

      expect(chunks, hasLength(2));
      expect(chunks[0].id, 'c1');
      expect(chunks[0].contentDelta, 'Hi');
      expect(chunks[1].contentDelta, '!');
    });

    test('returns Left(ConnectionFailure) on DioException', () async {
      when(() => mockDatasource.streamCompletion(
            baseUrl: baseUrl,
            model: model,
            messages: messages,
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenThrow(DioException(
        type: DioExceptionType.connectionTimeout,
        requestOptions: RequestOptions(path: ''),
      ));

      final result = await repository.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ConnectionFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('returns Left(ServerFailure) on ServerException', () async {
      when(() => mockDatasource.streamCompletion(
            baseUrl: baseUrl,
            model: model,
            messages: messages,
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenThrow(const ServerException('Server error', 500));

      final result = await repository.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect((failure as ServerFailure).statusCode, 500);
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns Left(ConnectionFailure) on generic Exception', () async {
      when(() => mockDatasource.streamCompletion(
            baseUrl: baseUrl,
            model: model,
            messages: messages,
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenThrow(Exception('Unexpected error'));

      final result = await repository.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ConnectionFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('passes all parameters through to datasource', () async {
      final streamController = StreamController<ChatChunkRemoteResponse>();
      when(() => mockDatasource.streamCompletion(
            baseUrl: baseUrl,
            model: model,
            messages: messages,
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
          )).thenAnswer((_) async => streamController.stream);

      final tools = <Map<String, dynamic>>[
        {'type': 'function', 'function': {'name': 'test'}},
      ];
      await repository.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
        tools: tools,
        apiKey: 'sk-key',
      );

      verify(() => mockDatasource.streamCompletion(
            baseUrl: baseUrl,
            model: model,
            messages: messages,
            tools: tools,
            apiKey: 'sk-key',
          )).called(1);

      streamController.close();
    });

    test('forwards temperature to datasource', () async {
      final streamController = StreamController<ChatChunkRemoteResponse>();
      when(() => mockDatasource.streamCompletion(
            baseUrl: baseUrl,
            model: model,
            messages: messages,
            tools: any(named: 'tools'),
            apiKey: any(named: 'apiKey'),
            temperature: any(named: 'temperature'),
          )).thenAnswer((_) async => streamController.stream);

      await repository.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
        temperature: 0.7,
      );

      verify(() => mockDatasource.streamCompletion(
            baseUrl: baseUrl,
            model: model,
            messages: messages,
            tools: null,
            apiKey: null,
            temperature: 0.7,
          )).called(1);

      streamController.close();
    });
  });
}
