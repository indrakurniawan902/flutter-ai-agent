import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  DioException dioErrorWith(
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

  group('FailureMessage.humanize - DioException', () {
    test('connectionTimeout maps to network message', () {
      final msg = FailureMessage.humanize(
        dioErrorWith(DioExceptionType.connectionTimeout),
      );

      expect(
        msg,
        'Network error occurred. Please check your internet connection.',
      );
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });

    test('badResponse 401 maps to authentication message', () {
      final msg = FailureMessage.humanize(
        dioErrorWith(DioExceptionType.badResponse, statusCode: 401),
      );

      expect(
        msg,
        'Authentication failed (HTTP 401). Verify your API key in Settings.',
      );
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });
  });

  group('FailureMessage.humanize - network and parsing', () {
    test('SocketException maps to network message', () {
      final msg = FailureMessage.humanize(
        const SocketException('Connection refused'),
      );

      expect(
        msg,
        'Network error occurred. Please check your internet connection.',
      );
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });

    test('TimeoutException maps to timeout message', () {
      final msg = FailureMessage.humanize(TimeoutException('timed out'));

      expect(msg, 'The request timed out. Please try again.');
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });

    test('FormatException maps to malformed data message', () {
      final msg = FailureMessage.humanize(const FormatException('bad json'));

      expect(msg, 'Received malformed data. Please try again.');
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });

    test('FormatException prefers the caller context over the generic message', () {
      final msg = FailureMessage.humanize(
        const FormatException('Unexpected character'),
        context: 'Malformed JSON in pairing payload',
      );

      expect(msg, 'Malformed JSON in pairing payload');
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });
  });

  group('FailureMessage.humanize - platform errors', () {
    test('permission_denied PlatformException maps to permission message', () {
      final msg = FailureMessage.humanize(
        PlatformException(code: 'permission_denied'),
      );

      expect(
        msg,
        'Permission denied. Grant the required permission in Settings.',
      );
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });

    test('generic PlatformException without context maps to device message',
        () {
      final msg = FailureMessage.humanize(
        PlatformException(code: 'camera_error', message: 'oops'),
      );

      expect(msg, 'The device rejected this action.');
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });

    test('generic PlatformException with context returns context', () {
      final msg = FailureMessage.humanize(
        PlatformException(code: 'camera_error', message: 'oops'),
        context: 'Could not open the camera',
      );

      expect(msg, 'Could not open the camera');
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });
  });

  group('FailureMessage.humanize - storage and fallback', () {
    test('SqliteException-shaped error maps to storage message', () {
      final msg = FailureMessage.humanize(
        Exception('SqliteException(5): database is locked'),
      );

      expect(msg, 'Local storage error. Please try again.');
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });

    test('bare Exception without context maps to generic message', () {
      final msg = FailureMessage.humanize(Exception('boom'));

      expect(msg, 'Something went wrong. Please try again.');
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });

    test('bare Exception with context returns context', () {
      final msg = FailureMessage.humanize(
        Exception('boom'),
        context: 'Could not read the clipboard',
      );

      expect(msg, 'Could not read the clipboard');
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });

    test('technical context is scrubbed to generic message', () {
      final msg = FailureMessage.humanize(
        Exception('boom'),
        context: '#0      Foo.bar (package:x/y.dart:12)',
      );

      expect(msg, 'Something went wrong. Please try again.');
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
      expect(msg, isNot(contains('#0 ')));
      expect(msg, isNot(contains('package:')));
    });
  });

  group('FailureMessage.fromDio', () {
    test('delegates canonical mapping for 401', () {
      final msg = FailureMessage.fromDio(
        dioErrorWith(DioExceptionType.badResponse, statusCode: 401),
      );

      expect(
        msg,
        'Authentication failed (HTTP 401). Verify your API key in Settings.',
      );
      expect(msg, isNot(contains('Exception(')));
      expect(msg, isNot(contains('SqliteException')));
      expect(msg, isNot(contains('DioException')));
      expect(msg, isNot(contains('PlatformException')));
    });
  });
}
