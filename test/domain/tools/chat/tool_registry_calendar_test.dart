import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCalendarServiceBase extends Mock implements CalendarServiceBase {}

void main() {
  late MockCalendarServiceBase calendarService;
  late ToolRegistry registry;

  const id = '3073';

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
  });

  setUp(() {
    calendarService = MockCalendarServiceBase();
    registry = ToolRegistry(calendarService: calendarService);
    when(() => calendarService.createEvent(
          title: any(named: 'title'),
          startTime: any(named: 'startTime'),
          endTime: any(named: 'endTime'),
          description: any(named: 'description'),
        )).thenAnswer((_) async => Right(id));
  });

  ({DateTime? start, DateTime? end}) capturedTimes() {
    final invocation = verify(
      () => calendarService.createEvent(
        title: any(named: 'title'),
        startTime: captureAny(named: 'startTime'),
        endTime: captureAny(named: 'endTime'),
        description: any(named: 'description'),
      ),
    );
    return (
      start: invocation.captured[0] as DateTime?,
      end: invocation.captured[1] as DateTime?,
    );
  }

  group('calendar_create_event', () {
    test('parses ISO 8601 with UTC offset to that instant', () async {
      final res = await registry.executeTool('calendar_create_event', {
        'title': 'Sync',
        'startTime': '2026-09-13T16:00:00+07:00',
        'endTime': '2026-09-13T17:00:00+07:00',
      });

      expect(res.isRight(), isTrue);
      final times = capturedTimes();
      expect(times.start!.toUtc(), DateTime.utc(2026, 9, 13, 9, 0, 0));
      expect(times.end!.toUtc(), DateTime.utc(2026, 9, 13, 10, 0, 0));
    });

    test('parses local time without offset (regression)', () async {
      final res = await registry.executeTool('calendar_create_event', {
        'title': 'Sync',
        'startTime': '2026-09-13T16:00:00',
        'endTime': '2026-09-13T17:00:00',
      });

      expect(res.isRight(), isTrue);
      final times = capturedTimes();
      expect(times.start!.year, 2026);
      expect(times.start!.month, 9);
      expect(times.start!.day, 13);
      expect(times.start!.hour, 16);
    });

    test('parses date-only to midnight of that date', () async {
      final res = await registry.executeTool('calendar_create_event', {
        'title': 'Sync',
        'startTime': '2026-09-14',
        'endTime': '2026-09-15',
      });

      expect(res.isRight(), isTrue);
      final times = capturedTimes();
      expect(times.start!.year, 2026);
      expect(times.start!.month, 9);
      expect(times.start!.day, 14);
      expect(times.start!.hour, 0);
      expect(times.start!.minute, 0);
    });

    test('accepts startDate/endDate aliases', () async {
      final res = await registry.executeTool('calendar_create_event', {
        'title': 'Sync',
        'startDate': '2026-09-13T16:00:00',
        'endDate': '2026-09-13T17:00:00',
      });

      expect(res.isRight(), isTrue);
      final times = capturedTimes();
      expect(times.start!.year, 2026);
      expect(times.start!.month, 9);
      expect(times.start!.day, 13);
      expect(times.start!.hour, 16);
      expect(times.end!.hour, 17);
    });

    test('startTime takes precedence over startDate', () async {
      final res = await registry.executeTool('calendar_create_event', {
        'title': 'Sync',
        'startTime': '2026-09-13T16:00:00',
        'startDate': '2020-01-01T00:00:00',
        'endTime': '2026-09-13T17:00:00',
        'endDate': '2020-01-01T01:00:00',
      });

      expect(res.isRight(), isTrue);
      final times = capturedTimes();
      expect(times.start!.hour, 16);
      expect(times.end!.hour, 17);
    });

    test('unparseable startTime returns ValidationFailure naming field',
        () async {
      final res = await registry.executeTool('calendar_create_event', {
        'title': 'Sync',
        'startTime': 'not-a-date',
        'endTime': '2026-09-13T17:00:00',
      });

      expect(res.isLeft(), isTrue);
      final failure = (res as Left).value;
      expect(failure, isA<ValidationFailure>());
      expect(failure.message, contains('startTime'));
      verifyNever(() => calendarService.createEvent(
            title: any(named: 'title'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
            description: any(named: 'description'),
          ));
    });

    test('unparseable endTime returns ValidationFailure naming field',
        () async {
      final res = await registry.executeTool('calendar_create_event', {
        'title': 'Sync',
        'startTime': '2026-09-13T16:00:00',
        'endTime': 'not-a-date',
      });

      expect(res.isLeft(), isTrue);
      final failure = (res as Left).value;
      expect(failure, isA<ValidationFailure>());
      expect(failure.message, contains('endTime'));
      verifyNever(() => calendarService.createEvent(
            title: any(named: 'title'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
            description: any(named: 'description'),
          ));
    });

    test('missing startTime key returns ValidationFailure', () async {
      final res = await registry.executeTool('calendar_create_event', {
        'title': 'Sync',
        'endTime': '2026-09-13T17:00:00',
      });

      expect(res.isLeft(), isTrue);
      expect((res as Left).value, isA<ValidationFailure>());
      verifyNever(() => calendarService.createEvent(
            title: any(named: 'title'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
            description: any(named: 'description'),
          ));
    });

    test('endTime before startTime returns ValidationFailure', () async {
      final res = await registry.executeTool('calendar_create_event', {
        'title': 'Sync',
        'startTime': '2026-09-13T17:00:00',
        'endTime': '2026-09-13T16:00:00',
      });

      expect(res.isLeft(), isTrue);
      expect((res as Left).value, isA<ValidationFailure>());
      verifyNever(() => calendarService.createEvent(
            title: any(named: 'title'),
            startTime: any(named: 'startTime'),
            endTime: any(named: 'endTime'),
            description: any(named: 'description'),
          ));
    });

    test('success message echoes start/end ISO strings', () async {
      final res = await registry.executeTool('calendar_create_event', {
        'title': 'Sync',
        'startTime': '2026-09-13T16:00:00',
        'endTime': '2026-09-13T17:00:00',
      });

      expect(res.isRight(), isTrue);
      final msg = (res as Right).value as String;
      expect(msg, contains('id: $id'));
      expect(
        msg,
        contains(DateTime(2026, 9, 13, 16).toIso8601String()),
      );
      expect(
        msg,
        contains(DateTime(2026, 9, 13, 17).toIso8601String()),
      );
    });
  });
}
