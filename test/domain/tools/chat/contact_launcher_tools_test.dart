import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:url_launcher/url_launcher.dart';

class MockContactsProvider extends Mock implements ContactsProvider {}

class MockUrlLauncherProvider extends Mock implements UrlLauncherProvider {}

void main() {
  late ContactLauncherTools tools;
  late MockContactsProvider mockContactsProvider;
  late MockUrlLauncherProvider mockUrlLauncherProvider;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(LaunchMode.platformDefault);
  });

  setUp(() {
    mockContactsProvider = MockContactsProvider();
    mockUrlLauncherProvider = MockUrlLauncherProvider();
    tools = ContactLauncherTools(
      contactsProvider: mockContactsProvider,
      urlLauncherProvider: mockUrlLauncherProvider,
    );
  });

  group('checkContactsPermission', () {
    test('returns true when contacts provider returns true', () async {
      when(() => mockContactsProvider.checkPermission())
          .thenAnswer((_) async => true);

      final result = await tools.checkContactsPermission();

      expect(result, isTrue);
      verify(() => mockContactsProvider.checkPermission()).called(1);
    });

    test('returns false when contacts provider returns false', () async {
      when(() => mockContactsProvider.checkPermission())
          .thenAnswer((_) async => false);

      final result = await tools.checkContactsPermission();

      expect(result, isFalse);
      verify(() => mockContactsProvider.checkPermission()).called(1);
    });
  });

  group('searchContacts', () {
    test('returns Right with JSON string of matched contacts', () async {
      final contactsData = [
        {
          'displayName': 'Alice Smith',
          'phones': ['+1234567890', '+1987654321'],
          'emails': ['alice@example.com'],
        },
        {
          'displayName': 'Bob Jones',
          'phones': ['+1122334455'],
          'emails': <String>[],
        },
      ];

      when(() => mockContactsProvider.searchContacts('Alice'))
          .thenAnswer((_) async => contactsData);

      final result = await tools.searchContacts('Alice');

      expect(result, isA<Right<Failure, String>>());
      result.fold(
        (failure) => fail('Expected Right but got Left: $failure'),
        (jsonString) {
          final decoded = jsonDecode(jsonString) as List<dynamic>;
          expect(decoded.length, 2);
          expect(decoded[0]['displayName'], 'Alice Smith');
          expect(decoded[0]['phones'], ['+1234567890', '+1987654321']);
          expect(decoded[0]['emails'], ['alice@example.com']);
          expect(decoded[1]['displayName'], 'Bob Jones');
        },
      );
      verify(() => mockContactsProvider.searchContacts('Alice')).called(1);
    });

    test('returns Right with empty list when no contacts matched', () async {
      when(() => mockContactsProvider.searchContacts('Unknown'))
          .thenAnswer((_) async => []);

      final result = await tools.searchContacts('Unknown');

      expect(result, const Right<Failure, String>('[]'));
      verify(() => mockContactsProvider.searchContacts('Unknown')).called(1);
    });

    test('returns Left(ServerFailure) when provider throws exception',
        () async {
      when(() => mockContactsProvider.searchContacts(any()))
          .thenThrow(Exception('Contacts DB error'));

      final result = await tools.searchContacts('Error');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Failed to search contacts'));
          expect(failure.message, isNot(contains('Exception')));
        },
        (_) => fail('Expected Left but got Right'),
      );
    });
  });

  group('openWhatsappChat', () {
    test('sanitizes phone and launches WhatsApp with message', () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenAnswer((_) async => true);
      when(
        () => mockUrlLauncherProvider.launchUrl(
          any(),
          mode: any(named: 'mode'),
        ),
      ).thenAnswer((_) async => true);

      final result = await tools.openWhatsappChat(
        '+62 812-3456-7890',
        message: 'Hello World!',
      );

      expect(result, isA<Right<Failure, String>>());
      final captured = verify(
        () => mockUrlLauncherProvider.launchUrl(
          captureAny(),
          mode: LaunchMode.externalApplication,
        ),
      ).captured;

      final uri = captured.first as Uri;
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/6281234567890');
      expect(uri.queryParameters['text'], 'Hello World!');
    });

    test('launches WhatsApp without message query when message is null or empty',
        () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenAnswer((_) async => true);
      when(
        () => mockUrlLauncherProvider.launchUrl(
          any(),
          mode: any(named: 'mode'),
        ),
      ).thenAnswer((_) async => true);

      final result = await tools.openWhatsappChat('+1 (555) 019-2834');

      expect(result, isA<Right<Failure, String>>());
      final captured = verify(
        () => mockUrlLauncherProvider.launchUrl(
          captureAny(),
          mode: LaunchMode.externalApplication,
        ),
      ).captured;

      final uri = captured.first as Uri;
      expect(uri.toString(), 'https://wa.me/15550192834');
    });

    test('returns Left(ServerFailure) when phone has no digits', () async {
      final result = await tools.openWhatsappChat('+++ --- ()');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Invalid phone number'));
        },
        (_) => fail('Expected Left but got Right'),
      );
      verifyNever(() => mockUrlLauncherProvider.canLaunchUrl(any()));
    });

    test('returns Left(ServerFailure) when canLaunchUrl returns false',
        () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenAnswer((_) async => false);

      final result = await tools.openWhatsappChat('+628123456789');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('No app available to handle WhatsApp'));
        },
        (_) => fail('Expected Left but got Right'),
      );
    });

    test('returns Left(ServerFailure) when launchUrl returns false', () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenAnswer((_) async => true);
      when(
        () => mockUrlLauncherProvider.launchUrl(
          any(),
          mode: any(named: 'mode'),
        ),
      ).thenAnswer((_) async => false);

      final result = await tools.openWhatsappChat('+628123456789');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Failed to open WhatsApp'));
        },
        (_) => fail('Expected Left but got Right'),
      );
    });

    test('returns Left(ServerFailure) when url launcher throws', () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenThrow(Exception('Platform launch error'));

      final result = await tools.openWhatsappChat('+628123456789');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Error opening WhatsApp'));
          expect(failure.message, isNot(contains('Exception')));
        },
        (_) => fail('Expected Left but got Right'),
      );
    });
  });

  group('openExternalUrl', () {
    test('successfully launches valid https URL', () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenAnswer((_) async => true);
      when(
        () => mockUrlLauncherProvider.launchUrl(
          any(),
          mode: any(named: 'mode'),
        ),
      ).thenAnswer((_) async => true);

      final result = await tools.openExternalUrl('https://flutter.dev/docs');

      expect(result, isA<Right<Failure, String>>());
      verify(
        () => mockUrlLauncherProvider.launchUrl(
          Uri.parse('https://flutter.dev/docs'),
          mode: LaunchMode.externalApplication,
        ),
      ).called(1);
    });

    test('successfully launches valid http URL', () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenAnswer((_) async => true);
      when(
        () => mockUrlLauncherProvider.launchUrl(
          any(),
          mode: any(named: 'mode'),
        ),
      ).thenAnswer((_) async => true);

      final result = await tools.openExternalUrl('http://example.com');

      expect(result, isA<Right<Failure, String>>());
      verify(
        () => mockUrlLauncherProvider.launchUrl(
          Uri.parse('http://example.com'),
          mode: LaunchMode.externalApplication,
        ),
      ).called(1);
    });

    test('returns Left(ServerFailure) on non-http/https scheme', () async {
      final result = await tools.openExternalUrl('ftp://example.com/file');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Invalid URL'));
        },
        (_) => fail('Expected Left but got Right'),
      );
      verifyNever(() => mockUrlLauncherProvider.canLaunchUrl(any()));
    });

    test('returns Left(ServerFailure) on invalid URL string', () async {
      final result = await tools.openExternalUrl('not a url');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Invalid URL'));
        },
        (_) => fail('Expected Left but got Right'),
      );
      verifyNever(() => mockUrlLauncherProvider.canLaunchUrl(any()));
    });

    test('returns Left(ServerFailure) when canLaunchUrl returns false',
        () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenAnswer((_) async => false);

      final result =
          await tools.openExternalUrl('https://invalid-browser-url.com');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Cannot launch URL'));
        },
        (_) => fail('Expected Left but got Right'),
      );
    });

    test('returns Left(ServerFailure) when launchUrl returns false', () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenAnswer((_) async => true);
      when(
        () => mockUrlLauncherProvider.launchUrl(
          any(),
          mode: any(named: 'mode'),
        ),
      ).thenAnswer((_) async => false);

      final result = await tools.openExternalUrl('https://example.com');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Failed to launch URL'));
        },
        (_) => fail('Expected Left but got Right'),
      );
    });

    test('returns Left(ServerFailure) when url launcher throws', () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenThrow(Exception('Browser failure'));

      final result = await tools.openExternalUrl('https://example.com');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Error launching URL'));
          expect(failure.message, isNot(contains('Exception')));
        },
        (_) => fail('Expected Left but got Right'),
      );
    });
  });

  group('openPhoneCall', () {
    test('sanitizes phone and launches phone dialer successfully', () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenAnswer((_) async => true);
      when(
        () => mockUrlLauncherProvider.launchUrl(
          any(),
          mode: any(named: 'mode'),
        ),
      ).thenAnswer((_) async => true);

      final result = await tools.openPhoneCall('+62 812-3456-789');

      expect(result, isA<Right<Failure, String>>());
      result.fold(
        (failure) => fail('Expected Right but got Left: $failure'),
        (message) => expect(message, contains('+62 812-3456-789')),
      );

      final captured = verify(
        () => mockUrlLauncherProvider.launchUrl(
          captureAny(),
          mode: LaunchMode.externalApplication,
        ),
      ).captured;

      final uri = captured.first as Uri;
      expect(uri.scheme, 'tel');
      expect(uri.path, '628123456789');
    });

    test('returns Left(ServerFailure) when phone has no digits', () async {
      final result = await tools.openPhoneCall('+++ --- ()');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Invalid phone number'));
        },
        (_) => fail('Expected Left but got Right'),
      );
      verifyNever(() => mockUrlLauncherProvider.canLaunchUrl(any()));
    });

    test('returns Left(ServerFailure) when canLaunchUrl returns false',
        () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenAnswer((_) async => false);

      final result = await tools.openPhoneCall('+628123456789');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(
            failure.message,
            contains('No app available to handle phone calls'),
          );
        },
        (_) => fail('Expected Left but got Right'),
      );
    });

    test('returns Left(ServerFailure) when launchUrl returns false', () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenAnswer((_) async => true);
      when(
        () => mockUrlLauncherProvider.launchUrl(
          any(),
          mode: any(named: 'mode'),
        ),
      ).thenAnswer((_) async => false);

      final result = await tools.openPhoneCall('+628123456789');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Failed to open the dialer'));
        },
        (_) => fail('Expected Left but got Right'),
      );
    });

    test('returns Left(ServerFailure) when url launcher throws', () async {
      when(() => mockUrlLauncherProvider.canLaunchUrl(any()))
          .thenThrow(Exception('Dialer launch failure'));

      final result = await tools.openPhoneCall('+628123456789');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Error opening phone dialer'));
          expect(failure.message, isNot(contains('Exception')));
        },
        (_) => fail('Expected Left but got Right'),
      );
    });
  });
}
