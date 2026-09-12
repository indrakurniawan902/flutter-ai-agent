import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/utils/dio_err_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const handler = DioErrHandler();

  DioException errorWith(
    DioExceptionType type, {
    int? statusCode,
    Object? error,
  }) {
    final requestOptions = RequestOptions(path: '/test');
    return DioException(
      requestOptions: requestOptions,
      type: type,
      error: error,
      response: statusCode == null
          ? null
          : Response<dynamic>(
              requestOptions: requestOptions,
              statusCode: statusCode,
            ),
    );
  }

  group('DioErrHandler - connection & timeout types', () {
    test('connectionTimeout maps to network error message', () {
      expect(
        handler.handleDioError(
          errorWith(DioExceptionType.connectionTimeout),
        ),
        'Network error occurred. Please check your internet connection.',
      );
    });

    test('connectionError maps to network error message', () {
      expect(
        handler.handleDioError(errorWith(DioExceptionType.connectionError)),
        'Network error occurred. Please check your internet connection.',
      );
    });

    test('sendTimeout maps to timeout message', () {
      expect(
        handler.handleDioError(errorWith(DioExceptionType.sendTimeout)),
        'Request timeout occurred',
      );
    });

    test('receiveTimeout maps to timeout message', () {
      expect(
        handler.handleDioError(errorWith(DioExceptionType.receiveTimeout)),
        'Request timeout occurred',
      );
    });

    test('badCertificate maps to TLS certificate message', () {
      expect(
        handler.handleDioError(errorWith(DioExceptionType.badCertificate)),
        'Unable to reach the server: TLS certificate verification failed.',
      );
    });

    test('cancel maps to cancellation message', () {
      expect(
        handler.handleDioError(errorWith(DioExceptionType.cancel)),
        'Request cancelled.',
      );
    });
  });

  group('DioErrHandler - badResponse status codes', () {
    test('401 maps to authentication failure message', () {
      expect(
        handler.handleDioError(
          errorWith(DioExceptionType.badResponse, statusCode: 401),
        ),
        'Authentication failed (HTTP 401). Verify your API key in Settings.',
      );
    });

    test('403 maps to forbidden message', () {
      expect(
        handler.handleDioError(
          errorWith(DioExceptionType.badResponse, statusCode: 403),
        ),
        'Access forbidden (HTTP 403). The active server rejected this API key. Verify it in Settings.',
      );
    });

    test('404 maps to unsupported endpoint message', () {
      expect(
        handler.handleDioError(
          errorWith(DioExceptionType.badResponse, statusCode: 404),
        ),
        'Endpoint not supported by the active server or router (HTTP 404).',
      );
    });

    test('429 maps to rate limit message', () {
      expect(
        handler.handleDioError(
          errorWith(DioExceptionType.badResponse, statusCode: 429),
        ),
        'Rate limit or quota exceeded (HTTP 429). Wait a moment or verify your API key quota in Settings.',
      );
    });

    test('500 maps to generic server failure with status code', () {
      expect(
        handler.handleDioError(
          errorWith(DioExceptionType.badResponse, statusCode: 500),
        ),
        'Server request failed (HTTP 500). Please try again later.',
      );
    });

    test('badResponse without a status code maps to unexpected message', () {
      expect(
        handler.handleDioError(errorWith(DioExceptionType.badResponse)),
        'An unexpected error occurred. Please try again later.',
      );
    });

    test('badResponse with unmapped status code includes the code', () {
      expect(
        handler.handleDioError(
          errorWith(DioExceptionType.badResponse, statusCode: 418),
        ),
        'Server request failed (HTTP 418). Please try again later.',
      );
    });
  });

  group('DioErrHandler - unknown type', () {
    test('unknown wrapping SocketException maps to network error message', () {
      expect(
        handler.handleDioError(
          errorWith(
            DioExceptionType.unknown,
            error: const SocketException('Connection refused'),
          ),
        ),
        'Network error occurred. Please check your internet connection.',
      );
    });

    test('unknown without SocketException maps to unexpected message', () {
      expect(
        handler.handleDioError(
          errorWith(DioExceptionType.unknown, error: Exception('boom')),
        ),
        'An unexpected error occurred. Please try again later.',
      );
    });
  });
}
