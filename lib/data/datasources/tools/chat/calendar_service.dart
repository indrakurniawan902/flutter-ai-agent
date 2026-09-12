import 'package:dartz/dartz.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:injectable/injectable.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart';

@LazySingleton(as: CalendarServiceBase)
class CalendarService implements CalendarServiceBase {
  CalendarService({DeviceCalendarPlugin? plugin})
      : _plugin = plugin ?? DeviceCalendarPlugin() {
    initTimeZone();
  }

  @factoryMethod
  factory CalendarService.create() => CalendarService();

  final DeviceCalendarPlugin _plugin;
  static bool _timeZoneInitialized = false;

  static void initTimeZone({String? timeZoneName, Duration? timeZoneOffset}) {
    if (_timeZoneInitialized &&
        timeZoneName == null &&
        timeZoneOffset == null) {
      return;
    }
    try {
      tz_data.initializeTimeZones();
      final name = timeZoneName ?? DateTime.now().timeZoneName;
      final offset = timeZoneOffset ?? DateTime.now().timeZoneOffset;

      if (tz.timeZoneDatabase.locations.containsKey(name)) {
        tz.setLocalLocation(tz.getLocation(name));
        _timeZoneInitialized = true;
        return;
      }

      for (final loc in tz.timeZoneDatabase.locations.values) {
        if (loc.currentTimeZone.offset == offset.inMilliseconds) {
          tz.setLocalLocation(loc);
          _timeZoneInitialized = true;
          return;
        }
      }
      _timeZoneInitialized = true;
    } catch (_) {
      // Keep default
    }
  }

  static tz.TZDateTime toLocalTz(DateTime dt) {
    initTimeZone();
    if (dt is tz.TZDateTime) return dt;
    if (dt.isUtc) {
      return tz.TZDateTime.from(dt, tz.local);
    }
    return tz.TZDateTime(
      tz.local,
      dt.year,
      dt.month,
      dt.day,
      dt.hour,
      dt.minute,
      dt.second,
      dt.millisecond,
      dt.microsecond,
    );
  }

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
        start: toLocalTz(startTime),
        end: toLocalTz(endTime),
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
