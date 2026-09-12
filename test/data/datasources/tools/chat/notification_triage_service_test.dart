import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockNotificationListenerPlatformWrapper extends Mock
    implements NotificationListenerPlatformWrapper {}

void main() {
  late MockNotificationListenerPlatformWrapper mockPlatform;
  late NotificationTriageService service;

  Map<String, dynamic> rawNotification({
    String id = 'n1',
    String packageName = 'com.whatsapp',
    String appName = 'WhatsApp',
    String title = 'Hello',
    String body = 'How are you?',
    int timestamp = 1700000000000,
  }) {
    return {
      'id': id,
      'packageName': packageName,
      'appName': appName,
      'title': title,
      'body': body,
      'timestamp': timestamp,
    };
  }

  setUp(() {
    mockPlatform = MockNotificationListenerPlatformWrapper();
    service = NotificationTriageService(platformWrapper: mockPlatform);
  });

  group('NotificationEntry', () {
    test('toJson/fromJson roundtrip preserves all fields', () {
      // Arrange
      final entry = NotificationEntry(
        id: 'n1',
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        title: 'Hi',
        body: 'Hello there',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      );

      // Act
      final restored = NotificationEntry.fromJson(entry.toJson());

      // Assert
      expect(restored, entry);
    });

    test('fromJson accepts ISO8601 timestamp strings', () {
      // Arrange
      final map = rawNotification(timestamp: 1700000000000)
        ..['timestamp'] =
            DateTime.fromMillisecondsSinceEpoch(1700000000000).toIso8601String();

      // Act
      final entry = NotificationEntry.fromJson(map);

      // Assert
      expect(entry.timestamp.millisecondsSinceEpoch, 1700000000000);
    });
  });

  group('OtpExtractionResult', () {
    test('empty has found=false and blank snippet', () {
      // Act
      final result = OtpExtractionResult.empty();

      // Assert
      expect(result.found, isFalse);
      expect(result.otp, isNull);
      expect(result.snippet, isEmpty);
    });

    test('toJson/fromJson roundtrip preserves all fields', () {
      // Arrange
      final result = OtpExtractionResult(
        found: true,
        otp: '482913',
        sender: 'WhatsApp',
        packageName: 'com.whatsapp',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        snippet: 'Your code is 482913',
      );

      // Act
      final restored =
          OtpExtractionResult.fromJson(jsonDecode(jsonEncode(result.toJson()))
              as Map<String, dynamic>);

      // Assert
      expect(restored, result);
    });
  });

  group('static helpers', () {
    test('isSensitive flags OTP and banking content', () {
      // Arrange
      final otpEntry = NotificationEntry(
        id: 's1',
        packageName: 'com.bank',
        appName: 'Bank',
        title: 'Verification',
        body: 'Your OTP is 482913',
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final plainEntry = NotificationEntry(
        id: 's1',
        packageName: 'com.bank',
        appName: 'Bank',
        title: 'Lunch plans',
        body: 'Lunch at noon?',
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      );

      // Act + Assert
      expect(NotificationTriageService.isSensitive(otpEntry), isTrue);
      expect(NotificationTriageService.isSensitive(plainEntry), isFalse);
    });

    test('resolveAppName maps known packages and falls back to last segment',
        () {
      expect(
        NotificationTriageService.resolveAppName('com.whatsapp'),
        'WhatsApp',
      );
      expect(
        NotificationTriageService.resolveAppName('com.example.mail'),
        'Mail',
      );
    });

    test('matchesAppFilter matches appName or packageName case-insensitively',
        () {
      // Arrange
      final entry = NotificationEntry(
        id: 'f1',
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        title: 'Hi',
        body: 'Hello',
        timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      );

      // Act + Assert
      expect(NotificationTriageService.matchesAppFilter(entry, null), isTrue);
      expect(NotificationTriageService.matchesAppFilter(entry, ''), isTrue);
      expect(
        NotificationTriageService.matchesAppFilter(entry, 'whats'),
        isTrue,
      );
      expect(
        NotificationTriageService.matchesAppFilter(entry, 'WHATSAPP'),
        isTrue,
      );
      expect(
        NotificationTriageService.matchesAppFilter(entry, 'telegram'),
        isFalse,
      );
    });

    test('extractOtp finds contextual and bare numeric codes', () {
      expect(
        NotificationTriageService.extractOtp('Your verification code is 482913'),
        '482913',
      );
      expect(
        NotificationTriageService.extractOtp('OTP: 1234 valid for 5 min'),
        '1234',
      );
      expect(NotificationTriageService.extractOtp('No code here!'), isNull);
    });
  });

  group('checkPermission / requestPermission', () {
    test('checkPermission delegates to platform wrapper', () async {
      // Arrange
      when(() => mockPlatform.isPermissionGranted())
          .thenAnswer((_) async => true);

      // Act
      final result = await service.checkPermission();

      // Assert
      expect(result, isTrue);
      verify(() => mockPlatform.isPermissionGranted()).called(1);
    });

    test('checkPermission returns false on platform exception', () async {
      // Arrange
      when(() => mockPlatform.isPermissionGranted())
          .thenThrow(Exception('boom'));

      // Act
      final result = await service.checkPermission();

      // Assert
      expect(result, isFalse);
    });

    test('requestPermission delegates to platform wrapper', () async {
      // Arrange
      when(() => mockPlatform.requestPermission())
          .thenAnswer((_) async => true);

      // Act
      final result = await service.requestPermission();

      // Assert
      expect(result, isTrue);
      verify(() => mockPlatform.requestPermission()).called(1);
    });

    test('requestPermission returns false on platform exception', () async {
      // Arrange
      when(() => mockPlatform.requestPermission())
          .thenThrow(Exception('boom'));

      // Act
      final result = await service.requestPermission();

      // Assert
      expect(result, isFalse);
    });
  });

  group('getRecentNotifications', () {
    test('returns newest-first entries with app names resolved', () async {
      // Arrange
      when(() => mockPlatform.getRecentNotifications(limit: 20)).thenAnswer(
        (_) async => [
          rawNotification(
            id: 'old',
            packageName: 'com.example.mail',
            appName: '',
            timestamp: 1700000000000,
          ),
          rawNotification(
            id: 'new',
            packageName: 'com.whatsapp',
            timestamp: 1700000100000,
          ),
        ],
      );

      // Act
      final result = await service.getRecentNotifications();

      // Assert
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('expected Right'),
        (entries) {
          expect(entries.map((e) => e.id), ['new', 'old']);
          expect(entries.last.appName, 'Mail');
        },
      );
    });

    test('filters out sensitive entries for privacy', () async {
      // Arrange
      when(() => mockPlatform.getRecentNotifications(limit: 20)).thenAnswer(
        (_) async => [
          rawNotification(id: 'plain', body: 'Lunch at noon?'),
          rawNotification(
            id: 'otp',
            title: 'Verification',
            body: 'Your OTP is 482913',
          ),
        ],
      );

      // Act
      final result = await service.getRecentNotifications();

      // Assert
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('expected Right'),
        (entries) => expect(entries.map((e) => e.id), ['plain']),
      );
    });

    test('applies appFilter to visible entries', () async {
      // Arrange
      when(() => mockPlatform.getRecentNotifications(limit: 20)).thenAnswer(
        (_) async => [
          rawNotification(id: 'wa', packageName: 'com.whatsapp'),
          rawNotification(
            id: 'tg',
            packageName: 'com.telegram.messenger',
            appName: 'Telegram',
            body: 'See you soon',
          ),
        ],
      );

      // Act
      final result =
          await service.getRecentNotifications(appFilter: 'telegram');

      // Assert
      result.fold(
        (_) => fail('expected Right'),
        (entries) => expect(entries.map((e) => e.id), ['tg']),
      );
    });

    test('returns ServerFailure on platform exception', () async {
      // Arrange
      when(() => mockPlatform.getRecentNotifications(limit: 20))
          .thenThrow(Exception('boom'));

      // Act
      final result = await service.getRecentNotifications();

      // Assert
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Notification triage error'));
        },
        (_) => fail('expected Left'),
      );
    });
  });

  group('readRecentNotificationsFormattedJson', () {
    test('returns JSON array of visible entries', () async {
      // Arrange
      when(() => mockPlatform.getRecentNotifications(limit: 20)).thenAnswer(
        (_) async => [rawNotification()],
      );

      // Act
      final result = await service.readRecentNotificationsFormattedJson();

      // Assert
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('expected Right'),
        (json) {
          final decoded = jsonDecode(json) as List;
          expect(decoded, hasLength(1));
          expect(decoded.first['id'], 'n1');
        },
      );
    });

    test('propagates failure from getRecentNotifications', () async {
      // Arrange
      when(() => mockPlatform.getRecentNotifications(limit: 20))
          .thenThrow(Exception('boom'));

      // Act
      final result = await service.readRecentNotificationsFormattedJson();

      // Assert
      expect(result, isA<Left<Failure, String>>());
    });
  });

  group('extractLatestOtp', () {
    test('returns latest OTP across notifications', () async {
      // Arrange
      when(() => mockPlatform.getRecentNotifications(limit: 20)).thenAnswer(
        (_) async => [
          rawNotification(
            id: 'old',
            title: 'Code',
            body: 'Your code is 111111',
            timestamp: 1700000000000,
          ),
          rawNotification(
            id: 'new',
            title: 'Code',
            body: 'Your code is 482913',
            timestamp: 1700000100000,
          ),
        ],
      );

      // Act
      final result = await service.extractLatestOtp();

      // Assert
      result.fold(
        (_) => fail('expected Right'),
        (otp) {
          expect(otp.found, isTrue);
          expect(otp.otp, '482913');
          expect(otp.sender, 'WhatsApp');
          expect(otp.packageName, 'com.whatsapp');
          expect(otp.snippet, contains('482913'));
        },
      );
    });

    test('returns empty result when no OTP present', () async {
      // Arrange
      when(() => mockPlatform.getRecentNotifications(limit: 20)).thenAnswer(
        (_) async => [rawNotification(body: 'Lunch at noon?')],
      );

      // Act
      final result = await service.extractLatestOtp();

      // Assert
      result.fold(
        (_) => fail('expected Right'),
        (otp) => expect(otp, OtpExtractionResult.empty()),
      );
    });

    test('respects appFilter when searching for OTP', () async {
      // Arrange
      when(() => mockPlatform.getRecentNotifications(limit: 20)).thenAnswer(
        (_) async => [
          rawNotification(
            id: 'wa',
            packageName: 'com.whatsapp',
            title: 'Code',
            body: 'Your code is 482913',
            timestamp: 1700000100000,
          ),
        ],
      );

      // Act
      final result = await service.extractLatestOtp(appFilter: 'telegram');

      // Assert
      result.fold(
        (_) => fail('expected Right'),
        (otp) => expect(otp.found, isFalse),
      );
    });

    test('returns ServerFailure on platform exception', () async {
      // Arrange
      when(() => mockPlatform.getRecentNotifications(limit: 20))
          .thenThrow(Exception('boom'));

      // Act
      final result = await service.extractLatestOtp();

      // Assert
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('OTP extraction error'));
        },
        (_) => fail('expected Left'),
      );
    });
  });

  group('extractLatestOtpFormattedJson', () {
    test('returns JSON encoding of OTP result', () async {
      // Arrange
      when(() => mockPlatform.getRecentNotifications(limit: 20)).thenAnswer(
        (_) async => [
          rawNotification(title: 'Code', body: 'Your code is 482913'),
        ],
      );

      // Act
      final result = await service.extractLatestOtpFormattedJson();

      // Assert
      result.fold(
        (_) => fail('expected Right'),
        (json) {
          final decoded = jsonDecode(json) as Map<String, dynamic>;
          expect(decoded['found'], isTrue);
          expect(decoded['otp'], '482913');
        },
      );
    });
  });
}
