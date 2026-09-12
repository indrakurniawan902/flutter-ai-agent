import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_ai_agent/core/constants/constants.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockSecureStorageService mockStorageService;

  setUp(() {
    mockStorageService = MockSecureStorageService();
  });

  group('SettingsCubit - loadSettings', () {
    test('initial state is SettingsInitial', () {
      when(() => mockStorageService.getBaseUrl()).thenAnswer((_) async => null);
      when(() => mockStorageService.getApiKey()).thenAnswer((_) async => null);
      when(() => mockStorageService.getModel()).thenAnswer((_) async => null);
      when(() => mockStorageService.getTemperature()).thenAnswer((_) async => null);

      final cubit = SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      );

      expect(cubit.state, const SettingsInitial());
    });

    test('constructor triggers loadSettings when autoLoad is true (default)', () async {
      when(() => mockStorageService.getBaseUrl())
          .thenAnswer((_) async => 'https://init-test.com/v1');
      when(() => mockStorageService.getApiKey())
          .thenAnswer((_) async => 'sk-init-key');
      when(() => mockStorageService.getModel())
          .thenAnswer((_) async => 'init-model');
      when(() => mockStorageService.getTemperature())
          .thenAnswer((_) async => 0.5);

      final cubit = SettingsCubit(secureStorageService: mockStorageService);

      await pumpEventQueue();

      expect(
        cubit.state,
        const SettingsLoaded(
          baseUrl: 'https://init-test.com/v1',
          apiKey: 'sk-init-key',
          model: 'init-model',
          temperature: 0.5,
        ),
      );
    });

    blocTest<SettingsCubit, SettingsState>(
      'emits [SettingsLoading, SettingsLoaded] with stored values when storage has config',
      setUp: () {
        when(() => mockStorageService.getBaseUrl())
            .thenAnswer((_) async => 'https://custom-router.com/v1');
        when(() => mockStorageService.getApiKey())
            .thenAnswer((_) async => 'sk-stored-key');
        when(() => mockStorageService.getModel())
            .thenAnswer((_) async => 'custom-model');
        when(() => mockStorageService.getTemperature())
            .thenAnswer((_) async => 0.9);
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.loadSettings(),
      expect: () => [
        const SettingsLoading(
          baseUrl: '',
          apiKey: '',
          model: '',
          temperature: 0.7,
        ),
        const SettingsLoaded(
          baseUrl: 'https://custom-router.com/v1',
          apiKey: 'sk-stored-key',
          model: 'custom-model',
          temperature: 0.9,
        ),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'emits [SettingsLoading, SettingsLoaded] with default values when storage is empty',
      setUp: () {
        when(() => mockStorageService.getBaseUrl()).thenAnswer((_) async => null);
        when(() => mockStorageService.getApiKey()).thenAnswer((_) async => null);
        when(() => mockStorageService.getModel()).thenAnswer((_) async => null);
        when(() => mockStorageService.getTemperature()).thenAnswer((_) async => null);
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.loadSettings(),
      expect: () => [
        const SettingsLoading(
          baseUrl: '',
          apiKey: '',
          model: '',
          temperature: 0.7,
        ),
        const SettingsLoaded(
          baseUrl: AppConstants.defaultBaseUrl,
          apiKey: '',
          model: AppConstants.defaultModel,
          temperature: AppConstants.defaultTemperature,
        ),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'emits [SettingsLoading, SettingsError] when storage read throws',
      setUp: () {
        when(() => mockStorageService.getBaseUrl())
            .thenThrow(Exception('Storage read failure'));
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.loadSettings(),
      expect: () => [
        const SettingsLoading(
          baseUrl: '',
          apiKey: '',
          model: '',
          temperature: 0.7,
        ),
        predicate<SettingsState>((state) {
          return state is SettingsError &&
              state.message.contains('Storage read failure');
        }),
      ],
    );
  });

  group('SettingsCubit - saveSettings', () {
    const validUrl = 'https://indra-9router.my.id/v1';
    const validApiKey = 'sk-valid-key-12345';
    const validModel = 'ag-glm';
    const validTemp = 0.7;

    blocTest<SettingsCubit, SettingsState>(
      'emits [SettingsSaving, SettingsSuccess] and calls storage when inputs are valid',
      setUp: () {
        when(() => mockStorageService.saveSettings(
              baseUrl: validUrl,
              apiKey: validApiKey,
              model: validModel,
              temperature: validTemp,
            )).thenAnswer((_) async {});
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.saveSettings(
        baseUrl: validUrl,
        apiKey: validApiKey,
        model: validModel,
        temperature: validTemp,
      ),
      expect: () => [
        const SettingsSaving(
          baseUrl: validUrl,
          apiKey: validApiKey,
          model: validModel,
          temperature: validTemp,
        ),
        const SettingsSuccess(
          baseUrl: validUrl,
          apiKey: validApiKey,
          model: validModel,
          temperature: validTemp,
          message: 'Settings saved successfully',
        ),
      ],
      verify: (_) {
        verify(() => mockStorageService.saveSettings(
              baseUrl: validUrl,
              apiKey: validApiKey,
              model: validModel,
              temperature: validTemp,
            )).called(1);
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'emits SettingsError when baseUrl format is invalid',
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.saveSettings(
        baseUrl: 'ftp://not-supported-scheme.com',
        apiKey: validApiKey,
        model: validModel,
        temperature: validTemp,
      ),
      expect: () => [
        const SettingsError(
          baseUrl: 'ftp://not-supported-scheme.com',
          apiKey: validApiKey,
          model: validModel,
          temperature: validTemp,
          message: 'Please enter a valid HTTP/HTTPS URL',
        ),
      ],
      verify: (_) {
        verifyNever(() => mockStorageService.saveSettings(
              baseUrl: any(named: 'baseUrl'),
              apiKey: any(named: 'apiKey'),
              model: any(named: 'model'),
              temperature: any(named: 'temperature'),
            ));
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'emits SettingsError when apiKey is empty',
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.saveSettings(
        baseUrl: validUrl,
        apiKey: '   ',
        model: validModel,
        temperature: validTemp,
      ),
      expect: () => [
        const SettingsError(
          baseUrl: validUrl,
          apiKey: '   ',
          model: validModel,
          temperature: validTemp,
          message: 'API Key cannot be empty',
        ),
      ],
      verify: (_) {
        verifyNever(() => mockStorageService.saveSettings(
              baseUrl: any(named: 'baseUrl'),
              apiKey: any(named: 'apiKey'),
              model: any(named: 'model'),
              temperature: any(named: 'temperature'),
            ));
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'clamps temperature to [0.0, 2.0] range',
      setUp: () {
        when(() => mockStorageService.saveSettings(
              baseUrl: validUrl,
              apiKey: validApiKey,
              model: validModel,
              temperature: 2.0,
            )).thenAnswer((_) async {});
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.saveSettings(
        baseUrl: validUrl,
        apiKey: validApiKey,
        model: validModel,
        temperature: 2.8,
      ),
      expect: () => [
        const SettingsSaving(
          baseUrl: validUrl,
          apiKey: validApiKey,
          model: validModel,
          temperature: 2.0,
        ),
        const SettingsSuccess(
          baseUrl: validUrl,
          apiKey: validApiKey,
          model: validModel,
          temperature: 2.0,
          message: 'Settings saved successfully',
        ),
      ],
      verify: (_) {
        verify(() => mockStorageService.saveSettings(
              baseUrl: validUrl,
              apiKey: validApiKey,
              model: validModel,
              temperature: 2.0,
            )).called(1);
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'emits [SettingsSaving, SettingsError] when storage write fails',
      setUp: () {
        when(() => mockStorageService.saveSettings(
              baseUrl: validUrl,
              apiKey: validApiKey,
              model: validModel,
              temperature: validTemp,
            )).thenThrow(Exception('Write failure'));
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.saveSettings(
        baseUrl: validUrl,
        apiKey: validApiKey,
        model: validModel,
        temperature: validTemp,
      ),
      expect: () => [
        const SettingsSaving(
          baseUrl: validUrl,
          apiKey: validApiKey,
          model: validModel,
          temperature: validTemp,
        ),
        predicate<SettingsState>((state) {
          return state is SettingsError &&
              state.message.contains('Write failure');
        }),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'resetToDefaults resets baseUrl, model, and temp to defaults while preserving apiKey by default',
      setUp: () {
        when(() => mockStorageService.saveBaseUrl(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveModel(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveTemperature(any())).thenAnswer((_) async {});
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      seed: () => const SettingsLoaded(
        baseUrl: 'https://custom-router.com/v1',
        apiKey: 'sk-user-key',
        model: 'custom-model',
        temperature: 1.5,
      ),
      act: (cubit) => cubit.resetToDefaults(),
      expect: () => [
        const SettingsLoaded(
          baseUrl: AppConstants.defaultBaseUrl,
          apiKey: 'sk-user-key',
          model: AppConstants.defaultModel,
          temperature: AppConstants.defaultTemperature,
        ),
      ],
      verify: (_) {
        verify(() => mockStorageService.saveBaseUrl(AppConstants.defaultBaseUrl)).called(1);
        verify(() => mockStorageService.saveModel(AppConstants.defaultModel)).called(1);
        verify(() => mockStorageService.saveTemperature(AppConstants.defaultTemperature)).called(1);
        verifyNever(() => mockStorageService.saveApiKey(any()));
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'resetToDefaults with preserveApiKey=false also clears apiKey in storage',
      setUp: () {
        when(() => mockStorageService.saveBaseUrl(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveModel(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveTemperature(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveApiKey(any())).thenAnswer((_) async {});
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      seed: () => const SettingsLoaded(
        baseUrl: 'https://custom-router.com/v1',
        apiKey: 'sk-user-key',
        model: 'custom-model',
        temperature: 1.5,
      ),
      act: (cubit) => cubit.resetToDefaults(preserveApiKey: false),
      expect: () => [
        const SettingsLoaded(
          baseUrl: AppConstants.defaultBaseUrl,
          apiKey: '',
          model: AppConstants.defaultModel,
          temperature: AppConstants.defaultTemperature,
        ),
      ],
      verify: (_) {
        verify(() => mockStorageService.saveApiKey('')).called(1);
      },
    );
  });

  group('SettingsCubit - updateFromProfile', () {
    blocTest<SettingsCubit, SettingsState>(
      'emits SettingsLoaded with profile properties',
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.updateFromProfile(
        const ServerProfile(
          id: 'p1',
          name: 'VPS Oracle',
          gatewayUrl: 'https://profile-url.com/v1',
          token: 'sk-profile-token',
          model: 'profile-model',
          temperature: 1.2,
        ),
      ),
      expect: () => [
        const SettingsLoaded(
          baseUrl: 'https://profile-url.com/v1',
          apiKey: 'sk-profile-token',
          model: 'profile-model',
          temperature: 1.2,
        ),
      ],
    );
  });
}
