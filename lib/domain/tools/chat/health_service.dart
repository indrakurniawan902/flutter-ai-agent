import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

/// Inner window for [HealthServiceBase.healthStatusFormattedJson].
/// Two sequential 6s platform calls (availability + grantedPermissions) are the
/// worst case; the registry's outer bound for `health_status`
/// ([ToolRegistry.longWindowToolTimeout], 25s) must stay strictly greater. This
/// tool has no permission pre-check stage, so this window alone must stay under
/// the device bridge's 30s budget.
const Duration kHealthStatusWindow = Duration(seconds: 13);

/// Inner window for [HealthServiceBase.getHealthDataFormattedJson].
/// Three sequential 6s platform calls (availability, grantedPermissions,
/// readMetric) are the worst case; the registry's outer bound for
/// `get_health_data` ([ToolRegistry.longWindowToolTimeout], 25s) must stay
/// strictly greater, and the permission pre-check plus this window must stay
/// under the device bridge's 30s budget (see
/// [RegisteredTool.effectivePermissionTimeout]).
const Duration kHealthReadWindow = Duration(seconds: 19);

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
