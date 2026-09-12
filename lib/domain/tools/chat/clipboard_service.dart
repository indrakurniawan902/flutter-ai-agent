import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

abstract class ClipboardServiceBase {
  Future<Either<Failure, String>> clipboardRead();
  Future<Either<Failure, String>> clipboardWrite(String text);
}
