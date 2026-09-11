import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failures.dart';

extension EitherX<L extends Failure, R> on Either<L, R> {
  R getOrThrow() {
    return fold(
      (failure) => throw Exception(failure.message),
      (value) => value,
    );
  }
}
