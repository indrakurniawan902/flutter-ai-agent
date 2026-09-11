import 'dart:collection';

import 'package:device_calendar/device_calendar.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/calendar_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../../helpers/mocks.dart';

void main() {
  late MockDeviceCalendarPlugin mockPlugin;
  late CalendarService service;

  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));
  });

  setUp(() {
    mockPlugin = MockDeviceCalendarPlugin();
    service = CalendarService(plugin: mockPlugin);
  });

  Result<UnmodifiableListView<Calendar>> calendarResult(
    List<Calendar> calendars,
  ) {
    return Result<UnmodifiableListView<Calendar>>()
      ..data = UnmodifiableListView(calendars);
  }

  Result<UnmodifiableListView<Event>> eventResult(List<Event> events) {
    return Result<UnmodifiableListView<Event>>()
      ..data = UnmodifiableListView(events);
  }

  group('listEvents', () {
    final startDate = DateTime(2026, 1, 1);
    final endDate = DateTime(2026, 1, 31);

    test('returns events from all calendars on success', () async {
      // Arrange
      when(() => mockPlugin.hasPermissions()).thenAnswer(
        (_) async => Result<bool>()..data = true,
      );
      when(() => mockPlugin.retrieveCalendars()).thenAnswer(
        (_) async => calendarResult([Calendar(id: 'cal1', name: 'Work')]),
      );
      final event = Event('cal1', title: 'Meeting');
      when(
        () => mockPlugin.retrieveEvents(
          'cal1',
          any(that: isA<RetrieveEventsParams>()),
        ),
      ).thenAnswer(
        (_) async => eventResult([event]),
      );

      // Act
      final result = await service.listEvents(
        startDate: startDate,
        endDate: endDate,
      );

      // Assert
      expect(result.isRight(), true);
      result.fold(
        (_) => fail('Expected Right'),
        (events) {
          expect(events.length, 1);
          expect(events.first.title, 'Meeting');
        },
      );
    });

    test('returns PermissionFailure when permission denied', () async {
      // Arrange
      when(() => mockPlugin.hasPermissions()).thenAnswer(
        (_) async => Result<bool>()..data = false,
      );
      when(() => mockPlugin.requestPermissions()).thenAnswer(
        (_) async => Result<bool>()..data = false,
      );

      // Act
      final result = await service.listEvents(
        startDate: startDate,
        endDate: endDate,
      );

      // Assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<PermissionFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('requests permission when not yet granted', () async {
      // Arrange
      when(() => mockPlugin.hasPermissions()).thenAnswer(
        (_) async => Result<bool>()..data = false,
      );
      when(() => mockPlugin.requestPermissions()).thenAnswer(
        (_) async => Result<bool>()..data = true,
      );
      when(() => mockPlugin.retrieveCalendars()).thenAnswer(
        (_) async => calendarResult([]),
      );

      // Act
      final result = await service.listEvents(
        startDate: startDate,
        endDate: endDate,
      );

      // Assert
      expect(result.isRight(), true);
      verify(() => mockPlugin.requestPermissions()).called(1);
    });

    test('returns ServerFailure when retrieveCalendars fails', () async {
      // Arrange
      when(() => mockPlugin.hasPermissions()).thenAnswer(
        (_) async => Result<bool>()..data = true,
      );
      when(() => mockPlugin.retrieveCalendars()).thenAnswer(
        (_) async {
          final result = Result<UnmodifiableListView<Calendar>>();
          result.errors.add(const ResultError(1, 'Error'));
          return result;
        },
      );

      // Act
      final result = await service.listEvents(
        startDate: startDate,
        endDate: endDate,
      );

      // Assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('returns empty list when no calendars exist', () async {
      // Arrange
      when(() => mockPlugin.hasPermissions()).thenAnswer(
        (_) async => Result<bool>()..data = true,
      );
      when(() => mockPlugin.retrieveCalendars()).thenAnswer(
        (_) async => calendarResult([]),
      );

      // Act
      final result = await service.listEvents(
        startDate: startDate,
        endDate: endDate,
      );

      // Assert
      expect(result.isRight(), true);
      result.fold(
        (_) => fail('Expected Right'),
        (events) => expect(events, isEmpty),
      );
    });

    test('returns ServerFailure on exception', () async {
      // Arrange
      when(() => mockPlugin.hasPermissions()).thenThrow(Exception('boom'));

      // Act
      final result = await service.listEvents(
        startDate: startDate,
        endDate: endDate,
      );

      // Assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('boom'));
        },
        (_) => fail('Expected Left'),
      );
    });
  });

  group('createEvent', () {
    final start = DateTime(2026, 3, 15, 10, 0);
    final end = DateTime(2026, 3, 15, 11, 0);

    test('creates event successfully', () async {
      // Arrange
      when(() => mockPlugin.hasPermissions()).thenAnswer(
        (_) async => Result<bool>()..data = true,
      );
      when(() => mockPlugin.retrieveCalendars()).thenAnswer(
        (_) async => calendarResult([Calendar(id: 'cal1', name: 'Work')]),
      );
      when(() => mockPlugin.createOrUpdateEvent(any())).thenAnswer(
        (_) async => Result<String>()..data = 'event-123',
      );

      // Act
      final result = await service.createEvent(
        title: 'Stand-up',
        startTime: start,
        endTime: end,
        description: 'Daily standup',
      );

      // Assert
      expect(result.isRight(), true);
      result.fold(
        (_) => fail('Expected Right'),
        (eventId) => expect(eventId, 'event-123'),
      );
    });

    test('returns PermissionFailure when permission denied', () async {
      // Arrange
      when(() => mockPlugin.hasPermissions()).thenAnswer(
        (_) async => Result<bool>()..data = false,
      );
      when(() => mockPlugin.requestPermissions()).thenAnswer(
        (_) async => Result<bool>()..data = false,
      );

      // Act
      final result = await service.createEvent(
        title: 'Stand-up',
        startTime: start,
        endTime: end,
      );

      // Assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<PermissionFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('returns ServerFailure when no calendars available', () async {
      // Arrange
      when(() => mockPlugin.hasPermissions()).thenAnswer(
        (_) async => Result<bool>()..data = true,
      );
      when(() => mockPlugin.retrieveCalendars()).thenAnswer(
        (_) async => calendarResult([]),
      );

      // Act
      final result = await service.createEvent(
        title: 'Stand-up',
        startTime: start,
        endTime: end,
      );

      // Assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('returns ServerFailure when createOrUpdateEvent fails', () async {
      // Arrange
      when(() => mockPlugin.hasPermissions()).thenAnswer(
        (_) async => Result<bool>()..data = true,
      );
      when(() => mockPlugin.retrieveCalendars()).thenAnswer(
        (_) async => calendarResult([Calendar(id: 'cal1', name: 'Work')]),
      );
      when(() => mockPlugin.createOrUpdateEvent(any())).thenAnswer(
        (_) async {
          final result = Result<String>();
          result.errors.add(const ResultError(1, 'Fail'));
          return result;
        },
      );

      // Act
      final result = await service.createEvent(
        title: 'Stand-up',
        startTime: start,
        endTime: end,
      );

      // Assert
      expect(result.isLeft(), true);
    });

    test('returns ServerFailure on exception', () async {
      // Arrange
      when(() => mockPlugin.hasPermissions()).thenThrow(Exception('boom'));

      // Act
      final result = await service.createEvent(
        title: 'Stand-up',
        startTime: start,
        endTime: end,
      );

      // Assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('boom'));
        },
        (_) => fail('Expected Left'),
      );
    });
  });
}
