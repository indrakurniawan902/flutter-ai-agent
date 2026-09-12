import 'dart:io';

import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@singleton
class DioErrHandler {
  const DioErrHandler();

  String handleDioError(DioException error) {
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
}
