import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dio/dio.dart';

class FailureMessage {
  FailureMessage._();

  /// Maps [error] to a short user-facing sentence.
  /// [context] is an OPTIONAL human-readable fallback (e.g. 'Could not read the clipboard').
  /// NEVER returns a string containing a raw exception dump.
  static String humanize(
    Object error, {
    String? context,
    StackTrace? stackTrace,
  }) {
    developer.log(
      '[FailureMessage] ${context ?? '-'} :: $error',
      name: 'FailureMessage',
      error: error,
      stackTrace: stackTrace,
    );

    String candidate;
    if (error is DioException) {
      candidate = fromDio(error);
    } else if (error is SocketException) {
      candidate =
          'Network error occurred. Please check your internet connection.';
    } else if (error is TimeoutException) {
      candidate = 'The request timed out. Please try again.';
    } else if (error is FormatException) {
      candidate = context ?? 'Received malformed data. Please try again.';
    } else if (error.runtimeType.toString().contains('MissingPluginException') ||
        error.toString().contains('MissingPluginException')) {
      candidate = 'This feature is not available on this device.';
    } else if (error.toString().startsWith('PlatformException(')) {
      final match = RegExp(r'^PlatformException\(([^,\)]+)').firstMatch(
        error.toString(),
      );
      final code = (match?.group(1) ?? '').toLowerCase();
      if (code.contains('permission') || code.contains('denied')) {
        candidate =
            'Permission denied. Grant the required permission in Settings.';
      } else {
        candidate = context ?? 'The device rejected this action.';
      }
    } else if (error.toString().contains('SqliteException') ||
        error.toString().contains('DatabaseException')) {
      candidate = 'Local storage error. Please try again.';
    } else {
      candidate = context ?? 'Something went wrong. Please try again.';
    }

    return _scrub(candidate, context);
  }

  /// Canonical DioException -> human message mapping (single source of truth).
  static String fromDio(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.connectionError:
        return 'Network error occurred. Please check your internet connection.';
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return 'Request timeout occurred';
      case DioExceptionType.badCertificate:
        return 'Unable to reach the server: TLS certificate verification failed.';
      case DioExceptionType.badResponse:
        final statusCode = error.response?.statusCode;
        switch (statusCode) {
          case 401:
            return 'Authentication failed (HTTP 401). Verify your API key in Settings.';
          case 403:
            return 'Access forbidden (HTTP 403). The active server rejected this API key. Verify it in Settings.';
          case 404:
            return 'Endpoint not supported by the active server or router (HTTP 404).';
          case 429:
            return 'Rate limit or quota exceeded (HTTP 429). Wait a moment or verify your API key quota in Settings.';
          case null:
            return 'An unexpected error occurred. Please try again later.';
          default:
            return 'Server request failed (HTTP $statusCode). Please try again later.';
        }
      case DioExceptionType.cancel:
        return 'Request cancelled.';
      case DioExceptionType.unknown:
        if (error.error is SocketException) {
          return 'Network error occurred. Please check your internet connection.';
        }
        return 'An unexpected error occurred. Please try again later.';
      default:
        return 'An unexpected error occurred. Please try again later.';
    }
  }

  static String _scrub(String candidate, String? context) {
    if (!_looksTechnical(candidate)) {
      return candidate;
    }
    final fallback = context ?? 'Something went wrong. Please try again.';
    if (!_looksTechnical(fallback)) {
      return fallback;
    }
    return 'Something went wrong. Please try again.';
  }

  static bool _looksTechnical(String value) {
    return value.contains('Exception(') ||
        value.contains('Error(') ||
        value.contains('SqliteException') ||
        value.contains('DatabaseException') ||
        value.contains('DioException') ||
        value.contains('PlatformException') ||
        value.contains('MissingPluginException') ||
        value.contains('#0 ') ||
        value.contains('package:') ||
        value.contains('.dart:') ||
        value.contains('/home/');
  }
}
