import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/intent_launcher_service_impl.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_ai_agent/domain/tools/chat/intent_launcher_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/system_settings_allow_list.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:url_launcher/url_launcher.dart';

class MockUrlLauncherProvider extends Mock implements UrlLauncherProvider {}

class MockSystemSettingsPlatformWrapper extends Mock
    implements SystemSettingsPlatformWrapper {}

class LaunchedUriRecorder {
  final List<Uri> launched = [];
  final List<LaunchMode> modes = [];
}

void main() {
  late IntentLauncherServiceImpl service;
  late MockUrlLauncherProvider launcher;
  late MockSystemSettingsPlatformWrapper settingsWrapper;
  late LaunchedUriRecorder recorder;

  setUpAll(() {
    registerFallbackValue(Uri.parse('https://example.com'));
    registerFallbackValue(LaunchMode.platformDefault);
  });

  setUp(() {
    launcher = MockUrlLauncherProvider();
    settingsWrapper = MockSystemSettingsPlatformWrapper();
    recorder = LaunchedUriRecorder();
    service = IntentLauncherServiceImpl(
      launcher: launcher,
      settingsWrapper: settingsWrapper,
    );
  });

  Uri lastLaunchedUri() {
    verify(() => launcher.launchUrl(any(), mode: any(named: 'mode')))
        .called(1);
    expect(recorder.modes.last, LaunchMode.externalApplication);
    return recorder.launched.last;
  }

  void stubLaunchOk() {
    when(() => launcher.canLaunchUrl(any())).thenAnswer((_) async => true);
    when(() => launcher.launchUrl(any(), mode: any(named: 'mode')))
        .thenAnswer((invocation) async {
      recorder.launched.add(invocation.positionalArguments.first as Uri);
      recorder.modes.add(invocation.namedArguments[#mode] as LaunchMode);
      return true;
    });
  }

  group('openWhatsappChat', () {
    test('launches wa.me https uri with encoded message', () async {
      stubLaunchOk();

      final result =
          await service.openWhatsappChat('+62 812-3456-7890', message: 'Hello World!');

      expect(result, isA<Right<Failure, String>>());
      result.fold(
        (_) => fail('Expected Right'),
        (msg) => expect(msg, 'WhatsApp chat opened for +62 812-3456-7890'),
      );
      final uri = lastLaunchedUri();
      expect(uri.scheme, 'https');
      expect(uri.host, 'wa.me');
      expect(uri.path, '/6281234567890');
      expect(uri.queryParameters['text'], 'Hello World!');
    });

    test('omits text query when message is null', () async {
      stubLaunchOk();

      final result = await service.openWhatsappChat('+6281234567890');

      expect(result.isRight(), isTrue);
      final uri = lastLaunchedUri();
      expect(uri.path, '/6281234567890');
      expect(uri.queryParameters.containsKey('text'), isFalse);
    });

    test('returns Left for empty normalized phone without launching', () async {
      final result = await service.openWhatsappChat('abc');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (f) {
          expect(f, isA<ServerFailure>());
          expect(f.message, 'Invalid phone number');
        },
        (_) => fail('Expected Left'),
      );
      verifyNever(() => launcher.canLaunchUrl(any()));
    });

    test('returns Left when no app can launch', () async {
      when(() => launcher.canLaunchUrl(any())).thenAnswer((_) async => false);

      final result = await service.openWhatsappChat('+6281234567890');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (f) => expect(f.message, 'No app available to handle WhatsApp on this device'),
        (_) => fail('Expected Left'),
      );
      verifyNever(() => launcher.launchUrl(any(), mode: any(named: 'mode')));
    });

    test('returns Left when launch returns false', () async {
      when(() => launcher.canLaunchUrl(any())).thenAnswer((_) async => true);
      when(() => launcher.launchUrl(any(), mode: any(named: 'mode')))
          .thenAnswer((_) async => false);

      final result = await service.openWhatsappChat('+6281234567890');

      result.fold(
        (f) => expect(f.message, contains('Failed to open WhatsApp')),
        (_) => fail('Expected Left'),
      );
    });

    test('returns Left when launcher throws', () async {
      when(() => launcher.canLaunchUrl(any()))
          .thenThrow(Exception('boom'));

      final result = await service.openWhatsappChat('+6281234567890');

      result.fold(
        (f) {
          expect(f, isA<ServerFailure>());
          expect(f.message, contains('Error opening WhatsApp'));
          expect(f.message, contains('boom'));
        },
        (_) => fail('Expected Left'),
      );
    });
  });

  group('openMapNavigation', () {
    test('launches geo uri for coordinates', () async {
      stubLaunchOk();
      const lat = 41.5;
      const lng = -2.5;
      final coords = '$lat,$lng';

      final result = await service.openMapNavigation(latitude: lat, longitude: lng);

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (msg) => expect(msg, 'Opened map navigation for $coords'),
      );
      final uri = lastLaunchedUri();
      expect(uri.scheme, 'geo');
      expect(uri.path, coords);
      expect(uri.queryParameters['q'], coords);
    });

    test('launches geo 0,0 uri for query only', () async {
      stubLaunchOk();

      final result = await service.openMapNavigation(query: 'pizza');

      expect(result.isRight(), isTrue);
      final uri = lastLaunchedUri();
      expect(uri.scheme, 'geo');
      expect(uri.path, '0,0');
      expect(uri.queryParameters['q'], 'pizza');
    });

    test('returns Left when neither coordinates nor query provided', () async {
      final result = await service.openMapNavigation();

      result.fold(
        (f) => expect(
          f.message,
          'Provide coordinates or a query for map navigation',
        ),
        (_) => fail('Expected Left'),
      );
      verifyNever(() => launcher.canLaunchUrl(any()));
    });

    test('falls back to google maps https when geo not launchable', () async {
      const lat = 1.5;
      const lng = 2.5;
      final coords = '$lat,$lng';
      stubLaunchOk();
      when(() => launcher.canLaunchUrl(any())).thenAnswer((invocation) async {
        final uri = invocation.positionalArguments.first as Uri;
        return uri.scheme != 'geo';
      });

      final result =
          await service.openMapNavigation(latitude: lat, longitude: lng);

      expect(result.isRight(), isTrue);
      final uri = lastLaunchedUri();
      expect(uri.scheme, 'https');
      expect(uri.host, 'www.google.com');
      expect(uri.path, '/maps/search');
      expect(uri.queryParameters['query'], coords);
      expect(uri.queryParameters['api'], '1');
    });

    test('returns Left when neither geo nor https launchable', () async {
      when(() => launcher.canLaunchUrl(any())).thenAnswer((_) async => false);

      final result = await service.openMapNavigation(query: 'museum');

      result.fold(
        (f) => expect(f.message, 'No app available to handle map navigation'),
        (_) => fail('Expected Left'),
      );
      verifyNever(() => launcher.launchUrl(any(), mode: any(named: 'mode')));
    });

    test('returns Left when launcher throws', () async {
      when(() => launcher.canLaunchUrl(any())).thenThrow(Exception('map boom'));

      final result = await service.openMapNavigation(query: 'cafe');

      result.fold(
        (f) => expect(f.message, contains('Error opening map navigation')),
        (_) => fail('Expected Left'),
      );
    });
  });

  group('openEmailComposer', () {
    test('launches mailto uri with subject and body', () async {
      stubLaunchOk();

      final result = await service.openEmailComposer(
        to: 'a@b.com',
        subject: 'Hi there',
        body: 'Body text',
      );

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (msg) => expect(msg, 'Email composer opened'),
      );
      final uri = lastLaunchedUri();
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'a@b.com');
      expect(uri.queryParameters['subject'], 'Hi there');
      expect(uri.queryParameters['body'], 'Body text');
    });

    test('composes with only a body and empty recipient', () async {
      stubLaunchOk();

      final result = await service.openEmailComposer(body: 'note');

      expect(result.isRight(), isTrue);
      final uri = lastLaunchedUri();
      expect(uri.scheme, 'mailto');
      expect(uri.path, '');
      expect(uri.queryParameters['body'], 'note');
    });

    test('returns Left when nothing to compose', () async {
      final result = await service.openEmailComposer();

      result.fold(
        (f) => expect(f.message, 'Nothing to compose'),
        (_) => fail('Expected Left'),
      );
      verifyNever(() => launcher.canLaunchUrl(any()));
    });

    test('returns Left when no app can launch email', () async {
      when(() => launcher.canLaunchUrl(any())).thenAnswer((_) async => false);

      final result = await service.openEmailComposer(to: 'a@b.com');

      result.fold(
        (f) =>
            expect(f.message, 'No app available to handle email on this device'),
        (_) => fail('Expected Left'),
      );
    });

    test('returns Left when launch returns false', () async {
      when(() => launcher.canLaunchUrl(any())).thenAnswer((_) async => true);
      when(() => launcher.launchUrl(any(), mode: any(named: 'mode')))
          .thenAnswer((_) async => false);

      final result = await service.openEmailComposer(to: 'a@b.com');

      result.fold(
        (f) => expect(f.message, 'Failed to open email composer'),
        (_) => fail('Expected Left'),
      );
    });

    test('returns Left when launcher throws', () async {
      when(() => launcher.canLaunchUrl(any())).thenThrow(Exception('mail boom'));

      final result = await service.openEmailComposer(to: 'a@b.com');

      result.fold(
        (f) => expect(f.message, contains('Error opening email composer')),
        (_) => fail('Expected Left'),
      );
    });
  });

  group('launchSystemSetting', () {
    test('opens known setting via wrapper', () async {
      when(() => settingsWrapper.openSystemSettings('bluetooth'))
          .thenAnswer((_) async => true);

      final result = await service.launchSystemSetting('bluetooth');

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (msg) => expect(msg, 'Opened bluetooth settings'),
      );
      verify(() => settingsWrapper.openSystemSettings('bluetooth')).called(1);
    });

    test('normalizes case-insensitive input', () async {
      when(() => settingsWrapper.openSystemSettings(any()))
          .thenAnswer((_) async => true);

      final result = await service.launchSystemSetting('WIFI');

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (msg) => expect(msg, 'Opened wifi settings'),
      );
      verify(() => settingsWrapper.openSystemSettings('wifi')).called(1);
    });

    test('returns Left for unknown type without touching wrapper', () async {
      final result = await service.launchSystemSetting('nope');

      result.fold(
        (f) => expect(f.message, 'Unknown setting type: nope'),
        (_) => fail('Expected Left'),
      );
      verifyNever(() => settingsWrapper.openSystemSettings(any()));
    });

    test('returns Left when wrapper reports failure', () async {
      when(() => settingsWrapper.openSystemSettings('sound'))
          .thenAnswer((_) async => false);

      final result = await service.launchSystemSetting('sound');

      result.fold(
        (f) => expect(f.message, 'Failed to open sound settings'),
        (_) => fail('Expected Left'),
      );
    });

    test('returns Left when wrapper throws', () async {
      when(() => settingsWrapper.openSystemSettings(any()))
          .thenThrow(Exception('chan down'));

      final result = await service.launchSystemSetting('apps');

      result.fold(
        (f) {
          expect(f, isA<ServerFailure>());
          expect(f.message, contains('Error opening system settings'));
        },
        (_) => fail('Expected Left'),
      );
    });

    // --- T18.2: special-permission CTA pages (AGENTS.md §7) ---
    // Every value in the shared allow-list must reach the platform wrapper, so a
    // newly added CTA cannot pass the allow-list check and then die at the
    // Kotlin `when` (which surfaces to the user as "Failed to open ... settings").
    test('every allow-listed value maps to a non-null platform call', () async {
      when(() => settingsWrapper.openSystemSettings(any()))
          .thenAnswer((_) async => true);

      for (final value in SystemSettingsAllowList.values) {
        final result = await service.launchSystemSetting(value);

        expect(
          result.isRight(),
          isTrue,
          reason: 'launchSystemSetting("$value") should reach the platform layer',
        );
        result.fold(
          (f) => fail('Expected Right for "$value", got ${f.message}'),
          (msg) => expect(msg, 'Opened $value settings'),
        );
        verify(() => settingsWrapper.openSystemSettings(value)).called(1);
      }
    });

    test('maps the §7 permission CTA pages that have no runtime dialog', () {
      // Guard the exact values AGENTS.md §7 depends on.
      expect(
        SystemSettingsAllowList.values,
        containsAll(<String>[
          'notification_listener',
          'nfc',
          'app_details',
        ]),
      );
      // `notification_app_settings` is NOT a real Android action; the standard
      // reuses app_details instead.
      expect(
        SystemSettingsAllowList.values,
        isNot(contains('notification_app_settings')),
      );
    });

    test('opens notification_listener via wrapper', () async {
      when(() => settingsWrapper.openSystemSettings('notification_listener'))
          .thenAnswer((_) async => true);

      final result = await service.launchSystemSetting('notification_listener');

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (msg) => expect(msg, 'Opened notification_listener settings'),
      );
      verify(() => settingsWrapper.openSystemSettings('notification_listener'))
          .called(1);
    });

    test('opens nfc via wrapper', () async {
      when(() => settingsWrapper.openSystemSettings('nfc'))
          .thenAnswer((_) async => true);

      final result = await service.launchSystemSetting('NFC');

      expect(result.isRight(), isTrue);
      verify(() => settingsWrapper.openSystemSettings('nfc')).called(1);
    });

    test('opens app_details via wrapper', () async {
      when(() => settingsWrapper.openSystemSettings('app_details'))
          .thenAnswer((_) async => true);

      final result = await service.launchSystemSetting('app_details');

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (msg) => expect(msg, 'Opened app_details settings'),
      );
      verify(() => settingsWrapper.openSystemSettings('app_details')).called(1);
    });

    test('returns Left for unknown type without touching wrapper', () async {
      for (final bogus in <String>['nope', 'notification_app_settings', '']) {
        final result = await service.launchSystemSetting(bogus);

        result.fold(
          (f) => expect(f.message, 'Unknown setting type: $bogus'),
          (_) => fail('Expected Left for "$bogus"'),
        );
      }
      verifyNever(() => settingsWrapper.openSystemSettings(any()));
    });
  });
}
