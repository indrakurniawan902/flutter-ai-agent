import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/notification_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../../../../helpers/mocks.dart';

void main() {
  late MockFlutterLocalNotificationsPlugin mockPlugin;
  late NotificationService service;

  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('UTC'));

    registerFallbackValue(const InitializationSettings());
    registerFallbackValue(const NotificationDetails());
    registerFallbackValue(tz.TZDateTime.now(tz.local));
    registerFallbackValue(AndroidScheduleMode.exactAllowWhileIdle);
    registerFallbackValue(
      UILocalNotificationDateInterpretation.absoluteTime,
    );
  });

  setUp(() {
    mockPlugin = MockFlutterLocalNotificationsPlugin();
    service = NotificationService(plugin: mockPlugin);

    // Default: initialize succeeds
    when(() => mockPlugin.initialize(any())).thenAnswer((_) async => true);
  });

  group('sendLocalNotification', () {
    test('shows notification successfully', () async {
      // Arrange
      when(
        () => mockPlugin.show(
          any(),
          any(),
          any(),
          any(),
        ),
      ).thenAnswer((_) async {});

      // Act
      final result = await service.sendLocalNotification(
        title: 'Test Title',
        body: 'Test Body',
      );

      // Assert
      expect(result.isRight(), true);
      verify(
        () => mockPlugin.show(
          0,
          'Test Title',
          'Test Body',
          any(that: isA<NotificationDetails>()),
        ),
      ).called(1);
    });

    test('increments notification id on each call', () async {
      // Arrange
      when(
        () => mockPlugin.show(any(), any(), any(), any()),
      ).thenAnswer((_) async {});

      // Act
      await service.sendLocalNotification(title: 'A', body: 'B');
      await service.sendLocalNotification(title: 'C', body: 'D');

      // Assert
      verify(
        () => mockPlugin.show(
          0,
          'A',
          'B',
          any(that: isA<NotificationDetails>()),
        ),
      ).called(1);
      verify(
        () => mockPlugin.show(
          1,
          'C',
          'D',
          any(that: isA<NotificationDetails>()),
        ),
      ).called(1);
    });

    test('initializes plugin only once', () async {
      // Arrange
      when(
        () => mockPlugin.show(any(), any(), any(), any()),
      ).thenAnswer((_) async {});

      // Act
      await service.sendLocalNotification(title: 'A', body: 'B');
      await service.sendLocalNotification(title: 'C', body: 'D');

      // Assert
      verify(() => mockPlugin.initialize(any())).called(1);
    });

    test('returns ServerFailure on exception', () async {
      // Arrange
      when(
        () => mockPlugin.show(any(), any(), any(), any()),
      ).thenThrow(Exception('show failed'));

      // Act
      final result = await service.sendLocalNotification(
        title: 'Title',
        body: 'Body',
      );

      // Assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('show failed'));
        },
        (_) => fail('Expected Left'),
      );
    });
  });

  group('scheduleReminder', () {
    test('schedules notification with correct delay', () async {
      // Arrange
      when(
        () => mockPlugin.zonedSchedule(
          any(),
          any(),
          any(),
          any(),
          any(),
          uiLocalNotificationDateInterpretation: any(
            named: 'uiLocalNotificationDateInterpretation',
          ),
          androidScheduleMode: any(named: 'androidScheduleMode'),
        ),
      ).thenAnswer((_) async {});

      // Act
      final result = await service.scheduleReminder(
        title: 'Reminder',
        body: 'Do the thing',
        delayMinutes: 30,
      );

      // Assert
      expect(result.isRight(), true);

      final captured = verify(
        () => mockPlugin.zonedSchedule(
          any(),
          captureAny(),
          captureAny(),
          captureAny(),
          any(),
          uiLocalNotificationDateInterpretation: any(
            named: 'uiLocalNotificationDateInterpretation',
          ),
          androidScheduleMode: any(named: 'androidScheduleMode'),
        ),
      ).captured;

      expect(captured[0], 'Reminder');
      expect(captured[1], 'Do the thing');
      final scheduledDate = captured[2] as tz.TZDateTime;
      // Should be roughly 30 min from now (within a 2-min tolerance)
      final expectedApprox = tz.TZDateTime.now(tz.local).add(
        const Duration(minutes: 30),
      );
      expect(
        scheduledDate.difference(expectedApprox).inSeconds.abs(),
        lessThan(120),
      );
    });

    test('returns ServerFailure when delayMinutes is zero', () async {
      // Act
      final result = await service.scheduleReminder(
        title: 'Reminder',
        body: 'Body',
        delayMinutes: 0,
      );

      // Assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('positive'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns ServerFailure when delayMinutes is negative', () async {
      // Act
      final result = await service.scheduleReminder(
        title: 'Reminder',
        body: 'Body',
        delayMinutes: -5,
      );

      // Assert
      expect(result.isLeft(), true);
    });

    test('returns ServerFailure on exception', () async {
      // Arrange
      when(
        () => mockPlugin.zonedSchedule(
          any(),
          any(),
          any(),
          any(),
          any(),
          uiLocalNotificationDateInterpretation: any(
            named: 'uiLocalNotificationDateInterpretation',
          ),
          androidScheduleMode: any(named: 'androidScheduleMode'),
        ),
      ).thenThrow(Exception('schedule failed'));

      // Act
      final result = await service.scheduleReminder(
        title: 'Reminder',
        body: 'Body',
        delayMinutes: 10,
      );

      // Assert
      expect(result.isLeft(), true);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('schedule failed'));
        },
        (_) => fail('Expected Left'),
      );
    });
  });
}
