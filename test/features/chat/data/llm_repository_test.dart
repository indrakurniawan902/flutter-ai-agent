import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/features/chat/data/llm_repository.dart';
import 'package:flutter_ai_agent/features/chat/data/models/chat_models.dart';

import '../../../../test/helpers/mocks.dart';

void main() {
  late MockDio mockDio;
  late LlmRepository repository;

  const baseUrl = 'https://api.example.com/v1';
  const model = 'gpt-4';
  final messages = <Map<String, dynamic>>[
    {'role': 'user', 'content': 'Hello'},
  ];

  setUp(() {
    mockDio = MockDio();
    repository = LlmRepository(dio: mockDio);
  });

  setUpAll(() {
    registerFallbackValue(Options());
  });

  /// Helper to create a fake streaming response from SSE lines.
  Response<ResponseBody> fakeStreamResponse(List<String> sseLines) {
    final bytes = sseLines
        .map((line) => Uint8List.fromList(utf8.encode('$line\n')))
        .toList();

    final streamController = StreamController<Uint8List>();
    for (final chunk in bytes) {
      streamController.add(chunk);
    }
    streamController.close();

    final responseBody = ResponseBody(
      streamController.stream,
      200,
      headers: {
        'content-type': ['text/event-stream'],
      },
    );

    return Response<ResponseBody>(
      data: responseBody,
      statusCode: 200,
      requestOptions: RequestOptions(path: '$baseUrl/chat/completions'),
    );
  }

  void stubDioPost(Response<ResponseBody> response) {
    when(() => mockDio.post<ResponseBody>(
          any(),
          data: any(named: 'data'),
          options: any(named: 'options'),
        )).thenAnswer((_) async => response);
  }

  group('LlmRepository.streamCompletion', () {
    test('returns Right with stream of ChatChunks on success', () async {
      final sseLines = [
        'data: {"id":"c1","model":"gpt-4","choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}',
        'data: {"id":"c2","model":"gpt-4","choices":[{"delta":{"content":"!"},"finish_reason":null}]}',
        'data: {"id":"c3","model":"gpt-4","choices":[{"delta":{},"finish_reason":"stop"}]}',
        'data: [DONE]',
      ];
      stubDioPost(fakeStreamResponse(sseLines));

      final result = await repository.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
      );

      expect(result.isRight(), isTrue);

      final stream = result.getOrElse(() => const Stream<ChatChunk>.empty());
      final chunks = await stream.toList();

      expect(chunks, hasLength(3));
      expect(chunks[0].contentDelta, 'Hi');
      expect(chunks[1].contentDelta, '!');
      expect(chunks[2].finishReason, 'stop');
    });

    test('returns Right with tool_calls deltas', () async {
      final sseLines = [
        'data: {"id":"t1","model":"gpt-4","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"search","arguments":"{\\"q\\":\\""}}]},"finish_reason":null}]}',
        'data: {"id":"t2","model":"gpt-4","choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"dart\\"}"}}]},"finish_reason":null}]}',
        'data: {"id":"t3","model":"gpt-4","choices":[{"delta":{},"finish_reason":"tool_calls"}]}',
        'data: [DONE]',
      ];
      stubDioPost(fakeStreamResponse(sseLines));

      final result = await repository.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
      );

      final chunks =
          await result.getOrElse(() => const Stream<ChatChunk>.empty()).toList();

      expect(chunks, hasLength(3));
      expect(chunks[0].toolCallDeltas!.first.name, 'search');
      expect(chunks[0].toolCallDeltas!.first.id, 'call_1');
      expect(chunks[1].toolCallDeltas!.first.argumentsFragment, 'dart"}');
      expect(chunks[2].finishReason, 'tool_calls');
    });

    test('returns Left(ConnectionFailure) on connection timeout', () async {
      when(() => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
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

    test('returns Left(ConnectionFailure) on connection error', () async {
      when(() => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        type: DioExceptionType.connectionError,
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

    test('returns Left(ServerFailure) on bad response', () async {
      when(() => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        type: DioExceptionType.badResponse,
        response: Response(
          statusCode: 401,
          statusMessage: 'Unauthorized',
          requestOptions: RequestOptions(path: ''),
        ),
        requestOptions: RequestOptions(path: ''),
      ));

      final result = await repository.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect((failure as ServerFailure).statusCode, 401);
          expect(failure.message, 'Unauthorized');
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns Left(ConnectionFailure) on unknown DioException', () async {
      when(() => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        type: DioExceptionType.unknown,
        message: 'Something went wrong',
        requestOptions: RequestOptions(path: ''),
      ));

      final result = await repository.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
      );

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ConnectionFailure>());
          expect(failure.message, 'Something went wrong');
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns Left(ConnectionFailure) on generic exception', () async {
      when(() => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(Exception('Unexpected'));

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

    test('passes apiKey header when provided', () async {
      stubDioPost(fakeStreamResponse(['data: [DONE]']));

      await repository.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
        apiKey: 'sk-test-key',
      );

      final captured = verify(() => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: captureAny(named: 'options'),
          )).captured;

      final options = captured.first as Options;
      expect(options.headers?['Authorization'], 'Bearer sk-test-key');
    });

    test('sends tools in request body when provided', () async {
      final tools = <Map<String, dynamic>>[
        {
          'type': 'function',
          'function': {
            'name': 'get_weather',
            'parameters': {'type': 'object'},
          },
        },
      ];
      stubDioPost(fakeStreamResponse(['data: [DONE]']));

      await repository.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
        tools: tools,
      );

      final captured = verify(() => mockDio.post<ResponseBody>(
            any(),
            data: captureAny(named: 'data'),
            options: any(named: 'options'),
          )).captured;

      final body = jsonDecode(captured.first as String) as Map<String, dynamic>;
      expect(body['tools'], isNotNull);
      expect(body['stream'], isTrue);
    });
  });
}
