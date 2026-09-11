import 'package:dio/dio.dart';

class DioErrHandler {
  const DioErrHandler();

  String handleDioError(DioException error) {
    switch (error.type) {
      case DioExceptionType.connectionTimeout:
        return 'Network error occurred. Please check your internet connection.';
      case DioExceptionType.receiveTimeout:
        return 'Request timeout occurred';
      case DioExceptionType.badResponse:
        if (error.response?.statusCode == 401) {
          return 'Authentication failed. Please login again.';
        }
        if (error.response?.statusCode == 404) {
          return 'Resource not found.';
        }
        if (error.response?.statusCode == 500) {
          return 'Server error occurred. Please try again later.';
        }
        return 'An unexpected error occurred. Please try again later.';
      default:
        return 'An unexpected error occurred. Please try again later.';
    }
  }
}
