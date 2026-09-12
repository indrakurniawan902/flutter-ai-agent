import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

@singleton
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
        return 'An unexpected error occurred. Please try again later.';
      default:
        return 'An unexpected error occurred. Please try again later.';
    }
  }
}
