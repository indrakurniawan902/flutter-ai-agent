import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:injectable/injectable.dart';

@singleton
class DioErrHandler {
  const DioErrHandler();

  String handleDioError(DioException error) {
    return FailureMessage.fromDio(error);
  }
}
