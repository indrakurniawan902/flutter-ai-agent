import 'package:dartz/dartz.dart';
import 'package:device_calendar/device_calendar.dart';

import 'package:flutter_ai_agent/common/failure.dart';

/// Abstraction for calendar operations, wrapping [DeviceCalendarPlugin].
///
/// Tools:
///  - listEvents: Tier 1 (auto-approve)
///  - createEvent: Tier 3 (HITL required)
abstract class CalendarServiceBase {
  /// Lists calendar events between [startDate] and [endDate].
  /// Tier 1: auto-approved.
  Future<Either<Failure, List<Event>>> listEvents({
    required DateTime startDate,
    required DateTime endDate,
  });

  /// Creates a calendar event. Tier 3: requires HITL approval.
  Future<Either<Failure, String>> createEvent({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    String? description,
  });
}
