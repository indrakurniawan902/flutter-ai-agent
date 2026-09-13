import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/intent_launcher_service_impl.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_ai_agent/domain/tools/chat/intent_launcher_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockUrlLauncherProvider extends Mock implements UrlLauncherProvider {}

class MockSystemSettingsPlatformWrapper extends Mock
    implements SystemSettingsPlatformWrapper {}

void main() {
  late IntentLauncherServiceImpl service;
  late MockSystemSettingsPlatformWrapper settingsWrapper;

  setUp(() {
    settingsWrapper = MockSystemSettingsPlatformWrapper();
    service = IntentLauncherServiceImpl(
      launcher: MockUrlLauncherProvider(),
      settingsWrapper: settingsWrapper,
    );
  });

  group('launchSystemSetting nfc', () {
    test('delegates nfc to the platform wrapper', () async {
      when(() => settingsWrapper.openSystemSettings('nfc'))
          .thenAnswer((_) async => true);

      final result = await service.launchSystemSetting('nfc');

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (msg) => expect(msg, 'Opened nfc settings'),
      );
      verify(() => settingsWrapper.openSystemSettings('nfc')).called(1);
    });

    test('returns Left for unknown name without touching the wrapper',
        () async {
      final result = await service.launchSystemSetting('nonsense');

      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (f) => expect(f.message, 'Unknown setting type: nonsense'),
        (_) => fail('Expected Left'),
      );
      verifyNever(() => settingsWrapper.openSystemSettings(any()));
    });
  });
}
