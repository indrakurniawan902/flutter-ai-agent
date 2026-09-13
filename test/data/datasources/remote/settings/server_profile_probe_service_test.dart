import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/data/datasources/remote/settings/server_profile_probe_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockDio mockDio;
  late ServerProfileProbeServiceImpl service;

  setUpAll(() {
    registerFallbackValue(Options());
  });

  setUp(() {
    mockDio = MockDio();
    service = ServerProfileProbeServiceImpl(dio: mockDio);
  });

  group('ServerProfileProbeServiceImpl - probeHermesNode (Mode A)', () {
    test('success 200 normalizes ws:// and /device/ws URL and returns models', () async {
      when(
        () => mockDio.get<dynamic>(
          'http://192.168.1.100:8080/models',
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          data: {
            'data': [
              {'id': 'hermes-3-llama-3.1-8b'},
              {'id': 'hermes-3-llama-3.1-70b'},
            ],
          },
          statusCode: 200,
          requestOptions: RequestOptions(path: 'http://192.168.1.100:8080/models'),
        ),
      );

      final result = await service.probeHermesNode(
        url: '  ws://192.168.1.100:8080/device/ws/  ',
        token: 'hermes_secret_token',
      );

      expect(result.isSuccess, isTrue);
      expect(result.models, ['hermes-3-llama-3.1-8b', 'hermes-3-llama-3.1-70b']);
      expect(result.latencyMs, isNotNull);
      expect(result.message, contains('Connected'));
      expect(result.message, contains('2 models'));

      final captured = verify(
        () => mockDio.get<dynamic>(
          'http://192.168.1.100:8080/models',
          options: captureAny(named: 'options'),
        ),
      ).captured.single as Options;

      expect(captured.headers?['Authorization'], 'Bearer hermes_secret_token');
      expect(captured.headers?['Accept'], 'application/json');
      expect(captured.sendTimeout, const Duration(seconds: 10));
      expect(captured.receiveTimeout, const Duration(seconds: 10));
    });

    test('success 200 parses string models list and handles empty models', () async {
      when(
        () => mockDio.get<dynamic>(
          'https://hermes.example.com/models',
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          data: {
            'models': ['qwen-2.5', 'llama-3.2'],
          },
          statusCode: 200,
          requestOptions: RequestOptions(path: 'https://hermes.example.com/models'),
        ),
      );

      final result = await service.probeHermesNode(
        url: 'wss://hermes.example.com/',
        token: 'token123',
      );

      expect(result.isSuccess, isTrue);
      expect(result.models, ['qwen-2.5', 'llama-3.2']);
      expect(result.message, contains('Connected'));
      expect(result.message, contains('2 models'));
    });

    test('success 200 with 0 models does not append models count to message', () async {
      when(
        () => mockDio.get<dynamic>(
          'http://localhost:8080/models',
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          data: {'data': <dynamic>[]},
          statusCode: 200,
          requestOptions: RequestOptions(path: 'http://localhost:8080/models'),
        ),
      );

      final result = await service.probeHermesNode(
        url: 'http://localhost:8080',
        token: 'token',
      );

      expect(result.isSuccess, isTrue);
      expect(result.models, isEmpty);
      expect(result.message, contains('Connected'));
      expect(result.message, isNot(contains('models')));
    });

    test('failure 401 returns failure ProbeResult', () async {
      when(
        () => mockDio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: 'http://192.168.1.100:8080/models'),
          response: Response(
            statusCode: 401,
            requestOptions: RequestOptions(path: 'http://192.168.1.100:8080/models'),
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await service.probeHermesNode(
        url: 'http://192.168.1.100:8080',
        token: 'invalid_token',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Connection failed'));
      expect(result.message, contains('401'));
      expect(result.models, isEmpty);
    });

    test('failure 500 returns failure ProbeResult', () async {
      when(
        () => mockDio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: 'http://192.168.1.100:8080/models'),
          response: Response(
            statusCode: 500,
            requestOptions: RequestOptions(path: 'http://192.168.1.100:8080/models'),
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await service.probeHermesNode(
        url: 'http://192.168.1.100:8080',
        token: 'token',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Connection failed'));
      expect(result.message, contains('500'));
      expect(result.models, isEmpty);
    });

    test('failure timeout returns failure ProbeResult', () async {
      when(
        () => mockDio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: 'http://192.168.1.100:8080/models'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      final result = await service.probeHermesNode(
        url: 'http://192.168.1.100:8080',
        token: 'token',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Connection failed'));
      expect(result.message.toLowerCase(), anyOf(contains('timeout'), contains('timed out')));
      expect(result.models, isEmpty);
    });

    test('non-Dio exception returns failure ProbeResult', () async {
      when(
        () => mockDio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenThrow(Exception('Socket closed'));

      final result = await service.probeHermesNode(
        url: 'http://192.168.1.100:8080',
        token: 'token',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Connection failed'));
      expect(result.message, contains('Socket closed'));
    });
  });

  group('ServerProfileProbeServiceImpl - probeOpenAi (Mode B)', () {
    test('success 200 normalizes url and appends /models', () async {
      when(
        () => mockDio.get<dynamic>(
          'https://api.openai.com/v1/models',
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          data: {
            'data': [
              {'id': 'gpt-4o'},
              {'id': 'gpt-4o-mini'},
            ],
          },
          statusCode: 200,
          requestOptions: RequestOptions(path: 'https://api.openai.com/v1/models'),
        ),
      );

      final result = await service.probeOpenAi(
        url: '  https://api.openai.com/v1/  ',
        apiKey: 'sk-test12345',
      );

      expect(result.isSuccess, isTrue);
      expect(result.models, ['gpt-4o', 'gpt-4o-mini']);
      expect(result.latencyMs, isNotNull);
      expect(result.message, contains('Connected'));
      expect(result.message, contains('2 models'));

      final captured = verify(
        () => mockDio.get<dynamic>(
          'https://api.openai.com/v1/models',
          options: captureAny(named: 'options'),
        ),
      ).captured.single as Options;

      expect(captured.headers?['Authorization'], 'Bearer sk-test12345');
      expect(captured.headers?['Accept'], 'application/json');
      expect(captured.sendTimeout, const Duration(seconds: 10));
      expect(captured.receiveTimeout, const Duration(seconds: 10));
    });

    test('success 200 does not duplicate /models when already present in url', () async {
      when(
        () => mockDio.get<dynamic>(
          'https://api.openai.com/v1/models',
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<dynamic>(
          data: {
            'data': [
              {'id': 'gpt-4o'},
            ],
          },
          statusCode: 200,
          requestOptions: RequestOptions(path: 'https://api.openai.com/v1/models'),
        ),
      );

      final result = await service.probeOpenAi(
        url: 'https://api.openai.com/v1/models',
        apiKey: 'sk-test12345',
        model: 'gpt-4o',
      );

      expect(result.isSuccess, isTrue);
      expect(result.models, ['gpt-4o']);
      expect(result.message, contains('Connected'));
      expect(result.message, contains('1 models'));
    });

    test('failure 401 returns failure ProbeResult', () async {
      when(
        () => mockDio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: 'https://api.openai.com/v1/models'),
          response: Response(
            statusCode: 401,
            requestOptions: RequestOptions(path: 'https://api.openai.com/v1/models'),
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await service.probeOpenAi(
        url: 'https://api.openai.com/v1',
        apiKey: 'invalid_key',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Connection failed'));
      expect(result.message, contains('401'));
      expect(result.models, isEmpty);
    });

    test('failure 500 returns failure ProbeResult', () async {
      when(
        () => mockDio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: 'https://api.openai.com/v1/models'),
          response: Response(
            statusCode: 500,
            requestOptions: RequestOptions(path: 'https://api.openai.com/v1/models'),
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await service.probeOpenAi(
        url: 'https://api.openai.com/v1',
        apiKey: 'key',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Connection failed'));
      expect(result.message, contains('500'));
      expect(result.models, isEmpty);
    });

    test('failure receive timeout returns failure ProbeResult', () async {
      when(
        () => mockDio.get<dynamic>(
          any(),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: 'https://api.openai.com/v1/models'),
          type: DioExceptionType.receiveTimeout,
        ),
      );

      final result = await service.probeOpenAi(
        url: 'https://api.openai.com/v1',
        apiKey: 'key',
      );

      expect(result.isSuccess, isFalse);
      expect(result.message, contains('Connection failed'));
      expect(result.message.toLowerCase(), anyOf(contains('timeout'), contains('timed out')));
      expect(result.models, isEmpty);
    });
  });
}
