import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/common/exception.dart';
import 'package:flutter_ai_agent/data/datasources/remote/chat/chat_datasource.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockDio mockDio;
  late ChatDatasourceImpl datasource;

  const baseUrl = 'https://api.example.com/v1';
  const model = 'gpt-4';
  final messages = <Map<String, dynamic>>[
    {'role': 'user', 'content': 'Hello'},
  ];

  setUp(() {
    mockDio = MockDio();
    datasource = ChatDatasourceImpl(dio: mockDio);
  });

  setUpAll(() {
    registerFallbackValue(Options());
  });

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

  group('ChatDatasourceImpl.streamCompletion', () {
    test('returns Stream<ChatChunkRemoteResponse> on success', () async {
      final sseLines = [
        'data: {"id":"c1","model":"gpt-4","choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}',
        'data: [DONE]',
      ];
      stubDioPost(fakeStreamResponse(sseLines));

      final stream = await datasource.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
      );

      final chunks = await stream.toList();
      expect(chunks, hasLength(1));
      expect(chunks.first.id, 'c1');
      expect(chunks.first.contentDelta, 'Hi');
    });

    test('throws ServerException on non-200 status', () async {
      when(() => mockDio.post<ResponseBody>(
            any(),
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => Response<ResponseBody>(
                data: ResponseBody(
                  Stream.empty(),
                  500,
                ),
                statusCode: 500,
                statusMessage: 'Internal Server Error',
                requestOptions: RequestOptions(
                    path: '$baseUrl/chat/completions'),
              ));

      expect(
        () => datasource.streamCompletion(
          baseUrl: baseUrl,
          model: model,
          messages: messages,
        ),
        throwsA(isA<ServerException>()),
      );
    });

    test('includes apiKey header when provided', () async {
      stubDioPost(fakeStreamResponse(['data: [DONE]']));

      await datasource.streamCompletion(
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

      await datasource.streamCompletion(
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

    test('sends temperature in request body when provided', () async {
      stubDioPost(fakeStreamResponse(['data: [DONE]']));

      await datasource.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
        temperature: 0.7,
      );

      final captured = verify(() => mockDio.post<ResponseBody>(
            any(),
            data: captureAny(named: 'data'),
            options: any(named: 'options'),
          )).captured;

      final body = jsonDecode(captured.first as String) as Map<String, dynamic>;
      expect(body['temperature'], 0.7);
      expect(body['stream'], isTrue);
    });

    test('omits temperature in request body when null', () async {
      stubDioPost(fakeStreamResponse(['data: [DONE]']));

      await datasource.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
        temperature: null,
      );

      final captured = verify(() => mockDio.post<ResponseBody>(
            any(),
            data: captureAny(named: 'data'),
            options: any(named: 'options'),
          )).captured;

      final body = jsonDecode(captured.first as String) as Map<String, dynamic>;
      expect(body.containsKey('temperature'), isFalse);
    });
  });
}
