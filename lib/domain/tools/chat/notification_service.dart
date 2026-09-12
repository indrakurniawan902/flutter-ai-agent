import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/core/errors/failures.dart';

/// Abstraction for local notification operations.
///
/// Tools:
///  - sendLocalNotification: Tier 1 (auto-approve)
///  - scheduleReminder: Tier 3 (HITL required)
abstract class NotificationServiceBase {
  /// Shows a notification immediately. Tier 1: auto-approved.
  Future<Either<Failure, void>> sendLocalNotification({
    required String title,
    required String body,
  });

  /// Schedules a reminder after [delayMinutes]. Tier 3: requires HITL approval.
  Future<Either<Failure, void>> scheduleReminder({
    required String title,
    required String body,
    required int delayMinutes,
  });
}
