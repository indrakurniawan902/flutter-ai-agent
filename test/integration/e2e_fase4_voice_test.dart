import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/myapp.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_router.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/device_context_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/pairing_parser.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late MockFlutterSecureStorage mockSecureStorage;
  late MockLlmRepository mockLlmRepository;
  late MockVoiceInputService mockVoiceInputService;
  late MockVoiceOutputService mockVoiceOutputService;
  late MockBackgroundService mockBackgroundService;
  late MockDeviceContextService mockDeviceContextService;

  late StreamController<String> transcriptionController;
  late StreamController<double> soundLevelController;
  late StreamController<VoiceInputStatus> voiceInputStatusController;
  late StreamController<String> voiceInputErrorController;

  late StreamController<VoiceOutputStatus> voiceOutputStatusController;
  late StreamController<String> voiceOutputErrorController;

  late StreamController<String> backgroundActionController;
  late Map<String, String> inMemoryStorage;
  bool isSpeakerMutedState = false;

  setUp(() async {
    await sl.reset();
    inMemoryStorage = {};
    isSpeakerMutedState = false;

    transcriptionController = StreamController<String>.broadcast();
    soundLevelController = StreamController<double>.broadcast();
    voiceInputStatusController = StreamController<VoiceInputStatus>.broadcast();
    voiceInputErrorController = StreamController<String>.broadcast();

    voiceOutputStatusController =
        StreamController<VoiceOutputStatus>.broadcast();
    voiceOutputErrorController = StreamController<String>.broadcast();

    backgroundActionController = StreamController<String>.broadcast();

    mockSecureStorage = MockFlutterSecureStorage();
    mockLlmRepository = MockLlmRepository();
    mockVoiceInputService = MockVoiceInputService();
    mockVoiceOutputService = MockVoiceOutputService();
    mockBackgroundService = MockBackgroundService();
    mockDeviceContextService = MockDeviceContextService();

    // Secure Storage Mocks
    when(() => mockSecureStorage.read(key: any(named: 'key')))
        .thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      return inMemoryStorage[key];
    });

    when(() => mockSecureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String;
      inMemoryStorage[key] = value;
    });

    when(() => mockSecureStorage.deleteAll())
        .thenAnswer((_) async => inMemoryStorage.clear());

    // Voice Input Service Mocks
    when(() => mockVoiceInputService.transcriptionStream)
        .thenAnswer((_) => transcriptionController.stream);
    when(() => mockVoiceInputService.soundLevelStream)
        .thenAnswer((_) => soundLevelController.stream);
    when(() => mockVoiceInputService.statusStream)
        .thenAnswer((_) => voiceInputStatusController.stream);
    when(() => mockVoiceInputService.errorStream)
        .thenAnswer((_) => voiceInputErrorController.stream);
    when(() => mockVoiceInputService.lastRecognizedWords).thenReturn('');
    when(() => mockVoiceInputService.isListening).thenReturn(false);
    when(() => mockVoiceInputService.isAvailable).thenReturn(true);
    when(() => mockVoiceInputService.dispose()).thenReturn(null);
    when(() => mockVoiceInputService.cancelListening()).thenAnswer((_) async {});
    when(() => mockVoiceInputService.startListening(
          listenFor: any(named: 'listenFor'),
          pauseFor: any(named: 'pauseFor'),
          localeId: any(named: 'localeId'),
        )).thenAnswer((_) async => const Right(unit));
    when(() => mockVoiceInputService.stopListening())
        .thenAnswer((_) async => const Right(''));

    // Voice Output Service Mocks
    when(() => mockVoiceOutputService.isMuted)
        .thenAnswer((_) => isSpeakerMutedState);
    when(() => mockVoiceOutputService.toggleMute()).thenAnswer((_) {
      isSpeakerMutedState = !isSpeakerMutedState;
    });
    when(() => mockVoiceOutputService.setMuted(any())).thenAnswer((inv) {
      isSpeakerMutedState = inv.positionalArguments[0] as bool;
    });
    when(() => mockVoiceOutputService.interrupt()).thenAnswer((_) async {});
    when(() => mockVoiceOutputService.statusStream)
        .thenAnswer((_) => voiceOutputStatusController.stream);
    when(() => mockVoiceOutputService.errorStream)
        .thenAnswer((_) => voiceOutputErrorController.stream);
    when(() => mockVoiceOutputService.dispose()).thenReturn(null);
    when(() => mockVoiceOutputService.speakText(
          any(),
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        )).thenAnswer((_) async => const Right(unit));

    // Background Service Mocks
    when(() => mockBackgroundService.actionStream)
        .thenAnswer((_) => backgroundActionController.stream);
    when(() => mockBackgroundService.getPendingAction())
        .thenAnswer((_) async => null);
    when(() => mockBackgroundService.clearPendingAction())
        .thenAnswer((_) async {});
    when(() => mockBackgroundService.isRunning())
        .thenAnswer((_) async => false);
    when(() => mockBackgroundService.isWakeLockHeld())
        .thenAnswer((_) async => false);
    when(() => mockBackgroundService.getTileState())
        .thenAnswer((_) async => QuickTileState.inactive);
    when(() => mockBackgroundService.startService(
          title: any(named: 'title'),
          content: any(named: 'content'),
        )).thenAnswer((_) async => const Right(true));
    when(() => mockBackgroundService.stopService())
        .thenAnswer((_) async => const Right(true));
    when(() => mockBackgroundService.dispose()).thenReturn(null);

    // Device Context Mocks
    when(() => mockDeviceContextService.deviceStatusFormattedJson())
        .thenAnswer((_) async => const Right(
              '{"battery_level":85,"battery_state":"discharging","is_charging":false,"connectivity":"wifi"}',
            ));
    when(() => mockDeviceContextService.systemInfoFormattedJson())
        .thenAnswer((_) async => const Right(
              '{"model":"Pixel 8 Pro","os":"Android 14"}',
            ));

    // Register all core and Fase 4 dependencies in GetIt
    sl.registerLazySingleton<FlutterSecureStorage>(() => mockSecureStorage);
    sl.registerLazySingleton<SecureStorageService>(
      () => SecureStorageService(storage: mockSecureStorage),
    );
    sl.registerLazySingleton<SettingsCubit>(
      () => SettingsCubit(secureStorageService: sl<SecureStorageService>()),
    );
    sl.registerLazySingleton<ServerProfileCubit>(
      () => ServerProfileCubit(
        secureStorageService: sl<SecureStorageService>(),
      ),
    );
    sl.registerLazySingleton<LlmRepository>(() => mockLlmRepository);
    sl.registerLazySingleton<ClipboardServiceBase>(() => MockClipboardService());
    sl.registerLazySingleton<LocationServiceBase>(() => MockLocationService());
    sl.registerLazySingleton<DeviceContextServiceBase>(
      () => mockDeviceContextService,
    );
    sl.registerLazySingleton<CameraVisionServiceBase>(
      () => MockCameraVisionService(),
    );
    sl.registerLazySingleton<CalendarServiceBase>(() => MockCalendarService());
    sl.registerLazySingleton<NotificationServiceBase>(
      () => MockNotificationService(),
    );

    // Fase 4 Services
    sl.registerLazySingleton<VoiceInputServiceBase>(
      () => mockVoiceInputService,
    );
    sl.registerLazySingleton<VoiceOutputServiceBase>(
      () => mockVoiceOutputService,
    );
    sl.registerLazySingleton<BackgroundServiceBase>(
      () => mockBackgroundService,
    );

    final toolRegistry = ToolRegistry();
    toolRegistry.registerDeviceContextTools(mockDeviceContextService);
    toolRegistry.registerVoiceTools(mockVoiceInputService);
    toolRegistry.registerVoiceOutputTools(mockVoiceOutputService);
    toolRegistry.registerBackgroundServiceTools(mockBackgroundService);
    sl.registerLazySingleton<ToolRegistry>(() => toolRegistry);

    sl.registerLazySingleton<PairingParser>(() => const PairingParser());

    sl.registerFactory<AgentCubit>(
      () => AgentCubit(
        llmRepository: sl<LlmRepository>(),
        toolRegistry: sl<ToolRegistry>(),
        secureStorageService: sl<SecureStorageService>(),
      ),
    );

    appRouter.go('/chat');
  });

  tearDown(() async {
    await sl.reset();
  });

  tearDownAll(() async {
    await transcriptionController.close();
    await soundLevelController.close();
    await voiceInputStatusController.close();
    await voiceInputErrorController.close();
    await voiceOutputStatusController.close();
    await voiceOutputErrorController.close();
    await backgroundActionController.close();
  });

  group('Fase 4 E2E Integration Suite', () {
    testWidgets(
      'Comprehensive E2E Pipeline: Voice Input -> STT transcription -> ReAct loop -> TTS Voice Output',
      (tester) async {
        const spokenTranscription =
            'Periksa status perangkat dan aktifkan layanan background';

        when(() => mockVoiceInputService.stopListening())
            .thenAnswer((_) async => const Right(spokenTranscription));

        // Setup multi-turn LLM response stream
        when(() => mockLlmRepository.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
            )).thenAnswer((invocation) async {
          final msgs =
              invocation.namedArguments[#messages] as List<Map<String, dynamic>>;
          final lastMsg = msgs.last;
          final role = lastMsg['role'] as String;
          final content = lastMsg['content'] as String?;

          // Turn 1: User prompt from voice transcription -> LLM calls device_status
          if (role == 'user' &&
              content != null &&
              content.contains('Periksa status perangkat')) {
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_device_1',
                    name: 'device_status',
                    argumentsFragment: '{}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          }

          // Turn 2: device_status executed -> LLM calls manage_background_service to start
          if (role == 'tool' && lastMsg['name'] == 'device_status') {
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_bg_1',
                    name: 'manage_background_service',
                    argumentsFragment:
                        '{"action":"start","title":"Flames AI Service","content":"Background automation active"}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          }

          // Turn 3: manage_background_service executed -> LLM produces final voice response
          if (role == 'tool' && lastMsg['name'] == 'manage_background_service') {
            return Right(Stream.fromIterable([
              const ChatChunk(
                contentDelta:
                    'Status baterai 85% dan layanan background Flames telah aktif.',
                finishReason: 'stop',
              ),
            ]));
          }

          return Right(Stream.fromIterable([
            const ChatChunk(contentDelta: 'Selesai.', finishReason: 'stop'),
          ]));
        });

        // 1. Launch App
        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        // 2. Start Voice Input via Mic Button
        final micButton = find.byKey(const Key('chat_mic_button'));
        expect(micButton, findsOneWidget);

        await tester.tap(micButton);
        await tester.pump();

        verify(() => mockVoiceInputService.startListening()).called(1);
        expect(find.byKey(const Key('voice_waveform_container')), findsOneWidget);

        // Simulate streaming sound level & transcription
        soundLevelController.add(0.8);
        transcriptionController.add(spokenTranscription);
        await tester.pump();

        // 3. User finishes speaking and taps Send on waveform
        final waveformSendButton =
            find.byKey(const Key('voice_waveform_send_button'));
        expect(waveformSendButton, findsOneWidget);

        await tester.tap(waveformSendButton);
        await tester.pump();

        verify(() => mockVoiceInputService.stopListening()).called(1);
        expect(find.byKey(const Key('voice_waveform_container')), findsNothing);

        // 4. Pump ReAct execution through AgentCubit and LLM stream
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();

        // 5. Verify Tool Invocations
        verify(() => mockDeviceContextService.deviceStatusFormattedJson())
            .called(1);
        verify(() => mockBackgroundService.startService(
              title: 'Flames AI Service',
              content: 'Background automation active',
            )).called(1);

        // 6. Verify UI Elements: user message, tool cards, assistant message
        expect(find.text(spokenTranscription), findsOneWidget);
        expect(find.text('Tool: device_status'), findsOneWidget);
        expect(find.text('Tool: manage_background_service'), findsOneWidget);
        expect(
          find.textContaining(
            'Status baterai 85% dan layanan background Flames telah aktif.',
          ),
          findsOneWidget,
        );

        // 7. Verify Voice Output (TTS): speakText automatically invoked with final response
        verify(() => mockVoiceOutputService.speakText(
              'Status baterai 85% dan layanan background Flames telah aktif.',
            )).called(1);
      },
    );

    testWidgets(
      'Barge-in Interruption: User tapping mic halts ongoing TTS voice playback immediately',
      (tester) async {
        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        final micButton = find.byKey(const Key('chat_mic_button'));
        expect(micButton, findsOneWidget);

        // User taps mic during playback -> interrupt must be called immediately
        await tester.tap(micButton);
        await tester.pump();

        verify(() => mockVoiceOutputService.interrupt()).called(1);
        verify(() => mockVoiceInputService.startListening()).called(1);
      },
    );

    testWidgets(
      'Background Automation: Quick Settings Tile & Notification Action dispatch triggers voice input & quick status',
      (tester) async {
        when(() => mockLlmRepository.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
            )).thenAnswer((invocation) async {
          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta:
                  'Semua sistem siap. Baterai 85% dan gateway terhubung.',
              finishReason: 'stop',
            ),
          ]));
        });

        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        // 1. Simulate Quick Settings Tile tap emitting "voice_input"
        backgroundActionController.add('voice_input');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.pump();

        verify(() => mockVoiceInputService.startListening()).called(1);
        expect(find.byKey(const Key('voice_waveform_container')), findsOneWidget);

        // Cancel voice input to reset state
        final cancelButton =
            find.byKey(const Key('voice_waveform_cancel_button'));
        await tester.tap(cancelButton);
        await tester.pump();

        // 2. Simulate Persistent Notification Action emitting "quick_status"
        backgroundActionController.add('quick_status');
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Verify status check prompt sent to agent
        expect(
          find.textContaining('Quick status check: summarize battery'),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Semua sistem siap. Baterai 85% dan gateway terhubung.',
          ),
          findsOneWidget,
        );

        // Verify TTS speaks the quick status response
        verify(() => mockVoiceOutputService.speakText(
              'Semua sistem siap. Baterai 85% dan gateway terhubung.',
            )).called(1);
      },
    );

    testWidgets(
      'Speaker Mute Control: Muting speaker suppresses TTS audio playback on agent response',
      (tester) async {
        when(() => mockLlmRepository.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
            )).thenAnswer((invocation) async {
          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta: 'Respon teks dalam mode senyap.',
              finishReason: 'stop',
            ),
          ]));
        });

        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        // Toggle speaker mute button in AppBar
        final speakerButton = find.byKey(const Key('chat_speaker_toggle'));
        expect(speakerButton, findsOneWidget);
        expect(find.byIcon(Icons.volume_up), findsOneWidget);

        await tester.tap(speakerButton);
        await tester.pumpAndSettle();

        verify(() => mockVoiceOutputService.toggleMute()).called(1);
        expect(find.byIcon(Icons.volume_off), findsOneWidget);

        // Send a message while muted
        final inputField = find.byKey(const Key('chat_input_field'));
        final sendButton = find.byKey(const Key('chat_send_button'));

        await tester.enterText(inputField, 'Kirim pesan tanpa suara');
        await tester.pump();
        await tester.tap(sendButton);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        expect(find.text('Respon teks dalam mode senyap.'), findsOneWidget);

        // Verify speakText was NEVER called because speaker is muted
        verifyNever(() => mockVoiceOutputService.speakText(any()));
      },
    );

    testWidgets(
      'Fase 4 Error Resilience: Gracefully handles microphone permission denied and TTS synthesis failure',
      (tester) async {
        when(() => mockVoiceInputService.startListening(
              listenFor: any(named: 'listenFor'),
              pauseFor: any(named: 'pauseFor'),
              localeId: any(named: 'localeId'),
            )).thenAnswer(
          (_) async => const Left(
            PermissionFailure(
              'Akses mikrofon ditolak. Aktifkan izin pada pengaturan perangkat.',
            ),
          ),
        );

        when(() => mockVoiceOutputService.speakText(any())).thenAnswer(
          (_) async => const Left(
            ServerFailure('TTS service temporarily unavailable (HTTP 503).'),
          ),
        );

        when(() => mockLlmRepository.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
            )).thenAnswer((invocation) async {
          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta: 'Respon agen tetap berjalan normal.',
              finishReason: 'stop',
            ),
          ]));
        });

        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        // 1. Trigger mic when permission is denied
        final micButton = find.byKey(const Key('chat_mic_button'));
        await tester.tap(micButton);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify SnackBar displayed and waveform container is not stuck open
        expect(
          find.text(
            'Akses mikrofon ditolak. Aktifkan izin pada pengaturan perangkat.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('voice_waveform_container')), findsNothing);

        // Clear SnackBar so it does not obscure input bar and send button
        ScaffoldMessenger.of(tester.element(find.byType(Scaffold)))
            .clearSnackBars();
        await tester.pumpAndSettle();

        // 2. Send text message to verify app stability and TTS error recovery
        final inputField = find.byKey(const Key('chat_input_field'));
        final sendButton = find.byKey(const Key('chat_send_button'));

        await tester.enterText(inputField, 'Cek ketahanan sistem');
        await tester.pump();
        await tester.tap(sendButton);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Message rendered properly despite TTS synthesis failure
        expect(find.text('Respon agen tetap berjalan normal.'), findsOneWidget);
        verify(() => mockVoiceOutputService.speakText(
              'Respon agen tetap berjalan normal.',
            )).called(1);
      },
    );
  });
}
