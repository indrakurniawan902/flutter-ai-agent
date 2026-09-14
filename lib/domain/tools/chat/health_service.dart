import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

abstract class HealthServiceBase {
  /// Availability + permission status of the health provider (Health Connect on
  /// Android). Returns a formatted JSON string, never throws.
  Future<Either<Failure, String>> healthStatusFormattedJson();

  /// Reads one metric between [startDate] and [endDate] (ISO 8601 strings;
  /// defaults: last 24 hours). Returns a formatted JSON string.
  Future<Either<Failure, String>> getHealthDataFormattedJson({
    required String metric,
    String? startDate,
    String? endDate,
  });

  /// True when the provider is available AND at least one supported read
  /// permission is granted. Never throws (returns false on error).
  Future<bool> checkPermission();
}
