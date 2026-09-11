import 'package:dartz/dartz.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:timezone/timezone.dart' as tz;

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

class CalendarService implements CalendarServiceBase {
  CalendarService({DeviceCalendarPlugin? plugin})
      : _plugin = plugin ?? DeviceCalendarPlugin();

  final DeviceCalendarPlugin _plugin;

  @override
  Future<Either<Failure, List<Event>>> listEvents({
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final permResult = await _plugin.hasPermissions();
      if (permResult.isSuccess && !(permResult.data ?? false)) {
        final reqResult = await _plugin.requestPermissions();
        if (!reqResult.isSuccess || !(reqResult.data ?? false)) {
          return const Left(
            PermissionFailure('Calendar permission denied'),
          );
        }
      }

      final calendarsResult = await _plugin.retrieveCalendars();
      if (!calendarsResult.isSuccess || calendarsResult.data == null) {
        return const Left(
          ServerFailure('Failed to retrieve calendars'),
        );
      }

      final allEvents = <Event>[];
      for (final calendar in calendarsResult.data!) {
        final eventsResult = await _plugin.retrieveEvents(
          calendar.id!,
          RetrieveEventsParams(
            startDate: startDate,
            endDate: endDate,
          ),
        );
        if (eventsResult.isSuccess && eventsResult.data != null) {
          allEvents.addAll(eventsResult.data!);
        }
      }

      return Right(allEvents);
    } catch (e) {
      return Left(ServerFailure('Calendar error: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> createEvent({
    required String title,
    required DateTime startTime,
    required DateTime endTime,
    String? description,
  }) async {
    try {
      final permResult = await _plugin.hasPermissions();
      if (permResult.isSuccess && !(permResult.data ?? false)) {
        final reqResult = await _plugin.requestPermissions();
        if (!reqResult.isSuccess || !(reqResult.data ?? false)) {
          return const Left(
            PermissionFailure('Calendar permission denied'),
          );
        }
      }

      final calendarsResult = await _plugin.retrieveCalendars();
      if (!calendarsResult.isSuccess ||
          calendarsResult.data == null ||
          calendarsResult.data!.isEmpty) {
        return const Left(
          ServerFailure('No calendars available'),
        );
      }

      final calendar = calendarsResult.data!.first;
      final event = Event(
        calendar.id,
        title: title,
        description: description,
        start: tz.TZDateTime.from(startTime, tz.local),
        end: tz.TZDateTime.from(endTime, tz.local),
      );

      final result = await _plugin.createOrUpdateEvent(event);
      if (result == null || !result.isSuccess || result.data == null) {
        return const Left(ServerFailure('Failed to create event'));
      }

      return Right(result.data!);
    } catch (e) {
      return Left(ServerFailure('Calendar error: $e'));
    }
  }
}
