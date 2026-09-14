import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_ai_agent/common/constant.dart';
import 'package:flutter_ai_agent/domain/entities/chat/piper_voice.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
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
      when(() => mockStorageService.getProgressiveToolPruning())
          .thenAnswer((_) async => true);

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
        when(() => mockStorageService.getProgressiveToolPruning())
            .thenAnswer((_) async => true);
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
        when(() => mockStorageService.getProgressiveToolPruning())
            .thenAnswer((_) async => true);
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
      'emits SettingsLoaded with progressiveToolPruning=false when storage has flag disabled',
      setUp: () {
        when(() => mockStorageService.getBaseUrl()).thenAnswer((_) async => null);
        when(() => mockStorageService.getApiKey()).thenAnswer((_) async => null);
        when(() => mockStorageService.getModel()).thenAnswer((_) async => null);
        when(() => mockStorageService.getTemperature()).thenAnswer((_) async => null);
        when(() => mockStorageService.getProgressiveToolPruning())
            .thenAnswer((_) async => false);
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.loadSettings(),
      expect: () => [
        const SettingsLoading(baseUrl: '', apiKey: '', model: '', temperature: 0.7),
        const SettingsLoaded(
          baseUrl: AppConstants.defaultBaseUrl,
          apiKey: '',
          model: AppConstants.defaultModel,
          temperature: AppConstants.defaultTemperature,
          progressiveToolPruning: false,
        ),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'persists progressiveToolPruning flag when saving settings',
      setUp: () {
        when(() => mockStorageService.saveSettings(
              baseUrl: 'https://flag-router.com/v1',
              apiKey: 'sk-flag-key',
              model: 'ag-glm',
              temperature: 0.7,
              progressiveToolPruning: false,
            )).thenAnswer((_) async {});
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        autoLoad: false,
      ),
      act: (cubit) => cubit.saveSettings(
        baseUrl: 'https://flag-router.com/v1',
        apiKey: 'sk-flag-key',
        model: 'ag-glm',
        temperature: 0.7,
        progressiveToolPruning: false,
      ),
      expect: () => [
        isA<SettingsSaving>()
            .having((s) => s.progressiveToolPruning, 'progressiveToolPruning', false),
        isA<SettingsSuccess>()
            .having((s) => s.progressiveToolPruning, 'progressiveToolPruning', false),
      ],
      verify: (_) {
        verify(() => mockStorageService.saveSettings(
              baseUrl: 'https://flag-router.com/v1',
              apiKey: 'sk-flag-key',
              model: 'ag-glm',
              temperature: 0.7,
              progressiveToolPruning: false,
            )).called(1);
      },
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
              state.message.contains('Failed to load settings');
        }),
      ],
    );
  });

  group('SettingsCubit - saveSettings', () {
    const validUrl = 'https://example.com/v1';
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
              progressiveToolPruning: true,
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
              progressiveToolPruning: true,
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
              progressiveToolPruning: any(named: 'progressiveToolPruning'),
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
              progressiveToolPruning: any(named: 'progressiveToolPruning'),
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
              progressiveToolPruning: true,
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
              progressiveToolPruning: true,
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
              progressiveToolPruning: true,
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
              state.message.contains('Failed to save settings');
        }),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'resetToDefaults resets baseUrl, model, and temp to defaults while preserving apiKey by default',
      setUp: () {
        when(() => mockStorageService.saveBaseUrl(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveModel(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveTemperature(any())).thenAnswer((_) async {});
        when(() => mockStorageService.saveProgressiveToolPruning(any()))
            .thenAnswer((_) async {});
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
        when(() => mockStorageService.saveProgressiveToolPruning(any()))
            .thenAnswer((_) async {});
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
          name: 'Remote Node',
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

  group('SettingsCubit - voice settings', () {
    late MockPiperVoiceStore mockVoiceStore;
    late MockVoiceOutputService mockVoiceService;

    setUp(() {
      mockVoiceStore = MockPiperVoiceStore();
      mockVoiceService = MockVoiceOutputService();
      registerFallbackValue(
        const PiperVoiceDescriptor(
          id: 'fallback',
          label: 'fallback',
          language: 'en_US',
          modelFileName: 'fallback.onnx',
          tarballName: 'fallback.tar.bz2',
          tarballMd5: 'md5',
          tarballSizeBytes: 1,
          downloadUrl: 'https://example.com/fallback',
        ),
      );
      registerFallbackValue(TtsEngineMode.system);
    });

    blocTest<SettingsCubit, SettingsState>(
      'loadVoiceSettings maps stored piper and probes every catalog id',
      setUp: () {
        when(() => mockStorageService.getTtsEngineMode())
            .thenAnswer((_) async => 'piper');
        when(() => mockStorageService.getPiperVoiceId())
            .thenAnswer((_) async => 'en_US-lessac-medium');
        when(() => mockVoiceStore.isVoiceReady(any()))
            .thenAnswer((_) async => false);
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        piperVoiceStore: mockVoiceStore,
        voiceOutputService: mockVoiceService,
        autoLoad: false,
      ),
      seed: () => const SettingsLoaded(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-key',
        model: 'ag-glm',
        temperature: 0.7,
      ),
      act: (cubit) => cubit.loadVoiceSettings(),
      expect: () => [
        predicate<SettingsState>((state) {
          if (state is! SettingsLoaded) return false;
          if (state.ttsEngineMode != TtsEngineMode.piper) return false;
          if (state.piperVoiceId != 'en_US-lessac-medium') return false;
          for (final descriptor in kPiperVoiceCatalog) {
            if (!state.piperVoiceReady.containsKey(descriptor.id)) {
              return false;
            }
          }
          return state.piperError == null;
        }),
      ],
      verify: (_) {
        for (final descriptor in kPiperVoiceCatalog) {
          verify(() => mockVoiceStore.isVoiceReady(descriptor.id)).called(1);
        }
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'downloadPiperVoice emits progress then loaded with id marked ready',
      setUp: () {
        when(
          () => mockVoiceStore.downloadVoice(
            any(),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async {});
        when(() => mockVoiceStore.isVoiceReady(any()))
            .thenAnswer((_) async => true);
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        piperVoiceStore: mockVoiceStore,
        voiceOutputService: mockVoiceService,
        autoLoad: false,
      ),
      seed: () => const SettingsLoaded(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-key',
        model: 'ag-glm',
        temperature: 0.7,
      ),
      act: (cubit) =>
          cubit.downloadPiperVoice('id_ID-news_tts-medium'),
      expect: () => [
        predicate<SettingsState>((state) {
          return state is SettingsVoiceDownloadInProgress &&
              state.downloadingVoiceId == 'id_ID-news_tts-medium' &&
              state.progress == 0;
        }),
        predicate<SettingsState>((state) {
          return state is SettingsLoaded &&
              state is! SettingsVoiceDownloadInProgress &&
              state.piperVoiceReady['id_ID-news_tts-medium'] == true &&
              state.piperError == null;
        }),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'downloadPiperVoice on integrity exception sets piperError and does not throw',
      setUp: () {
        when(
          () => mockVoiceStore.downloadVoice(
            any(),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenThrow(
          const VoiceModelIntegrityException('MD5 mismatch'),
        );
        when(() => mockVoiceStore.isVoiceReady(any()))
            .thenAnswer((_) async => false);
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        piperVoiceStore: mockVoiceStore,
        voiceOutputService: mockVoiceService,
        autoLoad: false,
      ),
      seed: () => const SettingsLoaded(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-key',
        model: 'ag-glm',
        temperature: 0.7,
      ),
      act: (cubit) =>
          cubit.downloadPiperVoice('id_ID-news_tts-medium'),
      expect: () => [
        isA<SettingsVoiceDownloadInProgress>(),
        predicate<SettingsState>((state) {
          return state is SettingsLoaded &&
              state is! SettingsVoiceDownloadInProgress &&
              state.piperError ==
                  'Voice model checksum mismatch - download rejected';
        }),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'deletePiperVoice marks the id not ready again',
      setUp: () {
        when(() => mockVoiceStore.deleteVoice(any()))
            .thenAnswer((_) async {});
        when(() => mockVoiceStore.isVoiceReady(any()))
            .thenAnswer((_) async => false);
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        piperVoiceStore: mockVoiceStore,
        voiceOutputService: mockVoiceService,
        autoLoad: false,
      ),
      seed: () => const SettingsLoaded(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-key',
        model: 'ag-glm',
        temperature: 0.7,
        piperVoiceReady: {'id_ID-news_tts-medium': true},
      ),
      act: (cubit) => cubit.deletePiperVoice('id_ID-news_tts-medium'),
      expect: () => [
        predicate<SettingsState>((state) {
          return state is SettingsLoaded &&
              state.piperVoiceReady['id_ID-news_tts-medium'] == false;
        }),
      ],
      verify: (_) {
        verify(
          () => mockVoiceStore.deleteVoice('id_ID-news_tts-medium'),
        ).called(1);
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'setTtsEngineMode persists piper and forwards to voice service',
      setUp: () {
        when(() => mockStorageService.saveTtsEngineMode(any()))
            .thenAnswer((_) async {});
        when(() => mockVoiceService.setPreferredEngineMode(any()))
            .thenAnswer((_) {});
      },
      build: () => SettingsCubit(
        secureStorageService: mockStorageService,
        piperVoiceStore: mockVoiceStore,
        voiceOutputService: mockVoiceService,
        autoLoad: false,
      ),
      seed: () => const SettingsLoaded(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-key',
        model: 'ag-glm',
        temperature: 0.7,
      ),
      act: (cubit) => cubit.setTtsEngineMode(TtsEngineMode.piper),
      expect: () => [
        predicate<SettingsState>((state) {
          return state is SettingsLoaded &&
              state.ttsEngineMode == TtsEngineMode.piper;
        }),
      ],
      verify: (_) {
        verify(() => mockStorageService.saveTtsEngineMode('piper')).called(1);
        verify(
          () => mockVoiceService.setPreferredEngineMode(TtsEngineMode.piper),
        ).called(1);
      },
    );

    test(
      'cubit built WITHOUT a voice store: loadVoiceSettings is a no-op that does not throw',
      () async {
        final cubit = SettingsCubit(
          secureStorageService: mockStorageService,
          autoLoad: false,
        );
        await expectLater(cubit.loadVoiceSettings(), completes);
        await cubit.close();
      },
    );
  });
}
