import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/notification_triage_service.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/security_policy.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockNotificationListenerPlatformWrapper mockPlatform;
  late NotificationTriageService service;

  final sampleRawNotifications = [
    {
      'id': '1_key1',
      'packageName': 'com.whatsapp',
      'title': 'WhatsApp',
      'text': 'Your WhatsApp code: 849-201. You can also tap on this link to verify.',
      'timestamp': 1710000000000,
    },
    {
      'id': '2_key2',
      'packageName': 'com.google.android.apps.messaging',
      'title': 'BCA',
      'text': 'Kode OTP Anda adalah 591823 untuk transaksi e-commerce. JANGAN BERIKAN KEPADA SIAPAPUN.',
      'timestamp': 1710000005000,
    },
    {
      'id': '3_key3',
      'packageName': 'org.telegram.messenger',
      'title': 'Telegram',
      'text': 'Login code: 49201. Do not give this code to anyone.',
      'timestamp': 1710000010000,
    },
    {
      'id': '4_key4',
      'packageName': 'com.bank.app',
      'title': 'Bank Alert',
      'text': 'Password internet banking anda berhasil diubah. Password baru: Rahasia123',
      'timestamp': 1710000015000,
    },
    {
      'id': '5_key5',
      'packageName': 'com.bank.app',
      'title': 'Bank Security',
      'text': 'Jangan bagikan PIN ATM atau CVV 492 Anda kepada siapapun.',
      'timestamp': 1710000020000,
    },
    {
      'id': '6_key6',
      'packageName': 'com.whatsapp',
      'title': 'Mom',
      'text': 'Don\'t forget to buy milk on your way home!',
      'timestamp': 1710000025000,
    },
  ];

  setUp(() {
    mockPlatform = MockNotificationListenerPlatformWrapper();
    service = NotificationTriageService(platformWrapper: mockPlatform);

    when(() => mockPlatform.isPermissionGranted())
        .thenAnswer((_) async => true);
    when(() => mockPlatform.requestPermission())
        .thenAnswer((_) async => true);
    when(() => mockPlatform.getRecentNotifications(limit: any(named: 'limit')))
        .thenAnswer((_) async => sampleRawNotifications);
    when(() => mockPlatform.clearNotifications())
        .thenAnswer((_) async => true);
  });

  group('NotificationEntry Model', () {
    test('supports value equality', () {
      final now = DateTime.now();
      final entry1 = NotificationEntry(
        id: '1',
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        title: 'Title',
        body: 'Body',
        timestamp: now,
      );
      final entry2 = NotificationEntry(
        id: '1',
        packageName: 'com.whatsapp',
        appName: 'WhatsApp',
        title: 'Title',
        body: 'Body',
        timestamp: now,
      );

      expect(entry1, equals(entry2));
    });

    test('fromJson and toJson produce valid representations', () {
      final json = {
        'id': 'notif_1',
        'packageName': 'org.telegram.messenger',
        'appName': 'Telegram',
        'title': 'Security Alert',
        'text': 'Your code is 12345',
        'timestamp': 1710000000000,
      };

      final entry = NotificationEntry.fromJson(json);
      expect(entry.id, 'notif_1');
      expect(entry.packageName, 'org.telegram.messenger');
      expect(entry.appName, 'Telegram');
      expect(entry.title, 'Security Alert');
      expect(entry.body, 'Your code is 12345');

      final serialized = entry.toJson();
      expect(serialized['id'], 'notif_1');
      expect(serialized['packageName'], 'org.telegram.messenger');
      expect(serialized['title'], 'Security Alert');
      expect(serialized['body'], 'Your code is 12345');
    });
  });

  group('OtpExtractionResult Model', () {
    test('supports value equality', () {
      final now = DateTime.now();
      final r1 = OtpExtractionResult(
        found: true,
        otp: '123456',
        sender: 'Telegram',
        packageName: 'org.telegram.messenger',
        timestamp: now,
        snippet: 'Code is 123456',
      );
      final r2 = OtpExtractionResult(
        found: true,
        otp: '123456',
        sender: 'Telegram',
        packageName: 'org.telegram.messenger',
        timestamp: now,
        snippet: 'Code is 123456',
      );

      expect(r1, equals(r2));
    });

    test('toJson serializes correctly', () {
      final r = OtpExtractionResult(
        found: true,
        otp: '654321',
        sender: 'WhatsApp',
        packageName: 'com.whatsapp',
        timestamp: DateTime(2026, 3, 10),
        snippet: 'Your code: 654321',
      );

      final json = r.toJson();
      expect(json['found'], true);
      expect(json['otp'], '654321');
      expect(json['sender'], 'WhatsApp');
      expect(json['packageName'], 'com.whatsapp');
    });
  });

  group('NotificationTriageService - Permissions', () {
    test('checkPermission delegates to platformWrapper', () async {
      final res = await service.checkPermission();
      expect(res, isTrue);
      verify(() => mockPlatform.isPermissionGranted()).called(1);
    });

    test('requestPermission delegates to platformWrapper', () async {
      final res = await service.requestPermission();
      expect(res, isTrue);
      verify(() => mockPlatform.requestPermission()).called(1);
    });
  });

  group('NotificationTriageService - getRecentNotifications & Filtering', () {
    test('returns notifications successfully when permission is granted', () async {
      final res = await service.getRecentNotifications();
      expect(res.isRight(), isTrue);

      final list = res.getOrElse(() => []);
      expect(list.isNotEmpty, isTrue);
    });

    test('returns PermissionFailure when permission is denied', () async {
      when(() => mockPlatform.isPermissionGranted()).thenAnswer((_) async => false);

      final res = await service.getRecentNotifications();
      expect(res.isLeft(), isTrue);
      res.fold(
        (failure) => expect(failure, isA<PermissionFailure>()),
        (_) => fail('Should be a failure'),
      );
    });

    test('privacy filter ignores banking passwords and sensitive credentials', () async {
      final res = await service.getRecentNotifications();
      expect(res.isRight(), isTrue);

      final list = res.getOrElse(() => []);
      // Should NOT include notification 4 (contains 'Password baru:') or notification 5 (contains 'CVV')
      for (final entry in list) {
        expect(entry.body.contains('Password baru:'), isFalse);
        expect(entry.body.contains('CVV'), isFalse);
        expect(entry.id, isNot('4_key4'));
        expect(entry.id, isNot('5_key5'));
      }
    });

    test('filters notifications by appFilter (whatsapp)', () async {
      final res = await service.getRecentNotifications(appFilter: 'whatsapp');
      expect(res.isRight(), isTrue);

      final list = res.getOrElse(() => []);
      expect(list.length, equals(2));
      for (final entry in list) {
        expect(entry.packageName, contains('whatsapp'));
      }
    });

    test('filters notifications by appFilter (sms / messaging)', () async {
      final res = await service.getRecentNotifications(appFilter: 'sms');
      expect(res.isRight(), isTrue);

      final list = res.getOrElse(() => []);
      expect(list.length, equals(1));
      expect(list.first.packageName, contains('messaging'));
    });

    test('respects limit parameter', () async {
      final res = await service.getRecentNotifications(limit: 1);
      expect(res.isRight(), isTrue);

      final list = res.getOrElse(() => []);
      expect(list.length, lessThanOrEqualTo(1));
    });

    test('readRecentNotificationsFormattedJson returns valid JSON', () async {
      final res = await service.readRecentNotificationsFormattedJson();
      expect(res.isRight(), isTrue);

      final jsonStr = res.getOrElse(() => '');
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded.containsKey('count'), isTrue);
      expect(decoded.containsKey('notifications'), isTrue);
      expect(decoded['notifications'], isA<List>());
    });

    test('returns ServerFailure when platform wrapper throws exception', () async {
      when(() => mockPlatform.getRecentNotifications(limit: any(named: 'limit')))
          .thenThrow(Exception('Platform channel error'));

      final res = await service.getRecentNotifications();
      expect(res.isLeft(), isTrue);
      res.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Should be a failure'),
      );
    });
  });

  group('NotificationTriageService - extractLatestOtp', () {
    test('extracts WhatsApp hyphenated/spaced OTP correctly', () async {
      final res = await service.extractLatestOtp(appFilter: 'whatsapp');
      expect(res.isRight(), isTrue);

      final otpResult = res.getOrElse(() => OtpExtractionResult.empty());
      expect(otpResult.found, isTrue);
      expect(otpResult.otp, '849201');
      expect(otpResult.packageName, 'com.whatsapp');
    });

    test('extracts Indonesian BCA OTP code correctly', () async {
      when(() => mockPlatform.getRecentNotifications(limit: any(named: 'limit')))
          .thenAnswer((_) async => [
                {
                  'id': 'bca_1',
                  'packageName': 'com.google.android.apps.messaging',
                  'title': 'BCA',
                  'text': 'Kode OTP Anda adalah 591823 untuk transaksi pembayaran Tokopedia.',
                  'timestamp': 1710000000000,
                }
              ]);

      final res = await service.extractLatestOtp();
      expect(res.isRight(), isTrue);

      final otpResult = res.getOrElse(() => OtpExtractionResult.empty());
      expect(otpResult.found, isTrue);
      expect(otpResult.otp, '591823');
      expect(otpResult.sender, 'BCA');
    });

    test('extracts Telegram 5-digit login code correctly', () async {
      when(() => mockPlatform.getRecentNotifications(limit: any(named: 'limit')))
          .thenAnswer((_) async => [
                {
                  'id': 'tg_1',
                  'packageName': 'org.telegram.messenger',
                  'title': 'Telegram',
                  'text': 'Login code: 49201. Do not give this code to anyone.',
                  'timestamp': 1710000000000,
                }
              ]);

      final res = await service.extractLatestOtp(appFilter: 'telegram');
      expect(res.isRight(), isTrue);

      final otpResult = res.getOrElse(() => OtpExtractionResult.empty());
      expect(otpResult.found, isTrue);
      expect(otpResult.otp, '49201');
    });

    test('extracts Google G-code format correctly', () async {
      when(() => mockPlatform.getRecentNotifications(limit: any(named: 'limit')))
          .thenAnswer((_) async => [
                {
                  'id': 'google_1',
                  'packageName': 'com.google.android.apps.messaging',
                  'title': 'Google',
                  'text': 'G-749204 is your Google verification code.',
                  'timestamp': 1710000000000,
                }
              ]);

      final res = await service.extractLatestOtp();
      expect(res.isRight(), isTrue);

      final otpResult = res.getOrElse(() => OtpExtractionResult.empty());
      expect(otpResult.found, isTrue);
      expect(otpResult.otp, '749204');
    });

    test('extracts 8-digit verification code correctly', () async {
      when(() => mockPlatform.getRecentNotifications(limit: any(named: 'limit')))
          .thenAnswer((_) async => [
                {
                  'id': 'service_1',
                  'packageName': 'com.service.app',
                  'title': 'Auth Service',
                  'text': 'Your security verification code is 19283746',
                  'timestamp': 1710000000000,
                }
              ]);

      final res = await service.extractLatestOtp();
      expect(res.isRight(), isTrue);

      final otpResult = res.getOrElse(() => OtpExtractionResult.empty());
      expect(otpResult.found, isTrue);
      expect(otpResult.otp, '19283746');
    });

    test('returns found: false when notification queue is empty', () async {
      when(() => mockPlatform.getRecentNotifications(limit: any(named: 'limit')))
          .thenAnswer((_) async => []);

      final res = await service.extractLatestOtp();
      expect(res.isRight(), isTrue);

      final otpResult = res.getOrElse(() => OtpExtractionResult.empty());
      expect(otpResult.found, isFalse);
      expect(otpResult.otp, isNull);
    });

    test('returns found: false when notifications exist but contain no OTP', () async {
      when(() => mockPlatform.getRecentNotifications(limit: any(named: 'limit')))
          .thenAnswer((_) async => [
                {
                  'id': 'notif_1',
                  'packageName': 'com.whatsapp',
                  'title': 'Mom',
                  'text': 'Dinner is ready at 7pm!',
                  'timestamp': 1710000000000,
                }
              ]);

      final res = await service.extractLatestOtp();
      expect(res.isRight(), isTrue);

      final otpResult = res.getOrElse(() => OtpExtractionResult.empty());
      expect(otpResult.found, isFalse);
      expect(otpResult.otp, isNull);
    });

    test('does NOT extract banking passwords as OTP (privacy protection)', () async {
      when(() => mockPlatform.getRecentNotifications(limit: any(named: 'limit')))
          .thenAnswer((_) async => [
                {
                  'id': 'bank_1',
                  'packageName': 'com.bank.app',
                  'title': 'Security Alert',
                  'text': 'Password baru internet banking: 928374',
                  'timestamp': 1710000000000,
                }
              ]);

      final res = await service.extractLatestOtp();
      expect(res.isRight(), isTrue);

      final otpResult = res.getOrElse(() => OtpExtractionResult.empty());
      expect(otpResult.found, isFalse);
      expect(otpResult.otp, isNull);
    });

    test('extractLatestOtpFormattedJson returns valid JSON', () async {
      final res = await service.extractLatestOtpFormattedJson(appFilter: 'whatsapp');
      expect(res.isRight(), isTrue);

      final jsonStr = res.getOrElse(() => '');
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded.containsKey('found'), isTrue);
      expect(decoded['found'], isTrue);
      expect(decoded['otp'], '849201');
    });

    test('returns PermissionFailure when permission is denied for extractLatestOtp', () async {
      when(() => mockPlatform.isPermissionGranted()).thenAnswer((_) async => false);

      final res = await service.extractLatestOtp();
      expect(res.isLeft(), isTrue);
      res.fold(
        (failure) => expect(failure, isA<PermissionFailure>()),
        (_) => fail('Should be a failure'),
      );
    });
  });

  group('ToolRegistry - Notification Triage Tools Registration & Execution', () {
    late ToolRegistry registry;
    late MockNotificationTriageService mockTriageService;

    setUp(() {
      registry = ToolRegistry();
      mockTriageService = MockNotificationTriageService();
      registry.registerNotificationTriageTools(mockTriageService);
    });

    test('registers read_recent_notifications as Tier 2 with permission check', () {
      expect(registry.hasTool('read_recent_notifications'), isTrue);
      final tool = registry.getTool('read_recent_notifications');
      expect(tool, isNotNull);
      expect(tool!.securityTier, equals(SecurityTier.tier2Permission));
      expect(tool.checkPermission, isNotNull);
    });

    test('registers extract_latest_otp as Tier 2 with permission check', () {
      expect(registry.hasTool('extract_latest_otp'), isTrue);
      final tool = registry.getTool('extract_latest_otp');
      expect(tool, isNotNull);
      expect(tool!.securityTier, equals(SecurityTier.tier2Permission));
      expect(tool.checkPermission, isNotNull);
    });

    test('executes read_recent_notifications via ToolRegistry successfully when permission granted', () async {
      when(() => mockTriageService.checkPermission()).thenAnswer((_) async => true);
      when(() => mockTriageService.readRecentNotificationsFormattedJson(
            limit: 5,
            appFilter: 'whatsapp',
          )).thenAnswer((_) async => const Right('{"count": 1, "notifications": []}'));

      final res = await registry.executeTool('read_recent_notifications', {
        'limit': 5,
        'appFilter': 'whatsapp',
      });

      expect(res.isRight(), isTrue);
      expect(res.getOrElse(() => ''), contains('"count": 1'));
    });

    test('denies read_recent_notifications via ToolRegistry when checkPermission returns false', () async {
      when(() => mockTriageService.checkPermission()).thenAnswer((_) async => false);

      final res = await registry.executeTool('read_recent_notifications', {});
      expect(res.isLeft(), isTrue);
      res.fold(
        (failure) => expect(failure, isA<PermissionFailure>()),
        (_) => fail('Should be PermissionFailure'),
      );
    });

    test('executes extract_latest_otp via ToolRegistry successfully when permission granted', () async {
      when(() => mockTriageService.checkPermission()).thenAnswer((_) async => true);
      when(() => mockTriageService.extractLatestOtpFormattedJson(
            appFilter: 'telegram',
          )).thenAnswer((_) async => const Right('{"found": true, "otp": "9999"}'));

      final res = await registry.executeTool('extract_latest_otp', {
        'appFilter': 'telegram',
      });

      expect(res.isRight(), isTrue);
      expect(res.getOrElse(() => ''), contains('"otp": "9999"'));
    });

    test('denies extract_latest_otp via ToolRegistry when checkPermission returns false', () async {
      when(() => mockTriageService.checkPermission()).thenAnswer((_) async => false);

      final res = await registry.executeTool('extract_latest_otp', {});
      expect(res.isLeft(), isTrue);
      res.fold(
        (failure) => expect(failure, isA<PermissionFailure>()),
        (_) => fail('Should be PermissionFailure'),
      );
    });
  });
}
