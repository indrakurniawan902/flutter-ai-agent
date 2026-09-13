import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

abstract class UrlReaderServiceBase {
  Future<Either<Failure, String>> fetchReadableText(String url);
}