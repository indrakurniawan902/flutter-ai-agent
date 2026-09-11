import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/di/injection_container.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/voice_input_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/voice_output_service.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_cubit.dart';
import 'package:flutter_ai_agent/features/chat/presentation/cubits/agent_state.dart';
import 'package:flutter_ai_agent/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter_ai_agent/features/settings/presentation/cubits/settings_cubit.dart';
import 'package:flutter_ai_agent/features/settings/presentation/cubits/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockAgentCubit mockAgentCubit;
  late MockSettingsCubit mockSettingsCubit;
  late MockVoiceInputService mockVoiceService;
  late MockVoiceOutputService mockVoiceOutputService;
  late StreamController<AgentState> stateController;
  late StreamController<String> transcriptionController;
  late StreamController<double> soundLevelController;
  late StreamController<VoiceInputStatus> statusController;
  late StreamController<String> errorController;

  setUp(() async {
    await sl.reset();
    mockAgentCubit = MockAgentCubit();
    mockSettingsCubit = MockSettingsCubit();
    mockVoiceService = MockVoiceInputService();
    mockVoiceOutputService = MockVoiceOutputService();

    stateController = StreamController<AgentState>.broadcast();
    transcriptionController = StreamController<String>.broadcast();
    soundLevelController = StreamController<double>.broadcast();
    statusController = StreamController<VoiceInputStatus>.broadcast();
    errorController = StreamController<String>.broadcast();

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.messages).thenReturn([]);
    when(() => mockAgentCubit.stream).thenAnswer((_) => stateController.stream);
    when(() => mockAgentCubit.sendMessage(any())).thenAnswer((_) async {});

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsLoaded(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o',
        temperature: 0.7,
      ),
    );
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockVoiceService.transcriptionStream)
        .thenAnswer((_) => transcriptionController.stream);
    when(() => mockVoiceService.soundLevelStream)
        .thenAnswer((_) => soundLevelController.stream);
    when(() => mockVoiceService.statusStream)
        .thenAnswer((_) => statusController.stream);
    when(() => mockVoiceService.errorStream)
        .thenAnswer((_) => errorController.stream);
    when(() => mockVoiceService.lastRecognizedWords).thenReturn('');
    when(() => mockVoiceService.isListening).thenReturn(false);
    when(() => mockVoiceService.isAvailable).thenReturn(true);
    when(() => mockVoiceService.dispose()).thenReturn(null);
    when(() => mockVoiceService.cancelListening())
        .thenAnswer((_) async {});
    when(() => mockVoiceService.stopListening())
        .thenAnswer((_) async => const Right(''));

    when(() => mockVoiceOutputService.isMuted).thenReturn(false);
    when(() => mockVoiceOutputService.interrupt()).thenAnswer((_) async {});
    when(() => mockVoiceOutputService.statusStream).thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceOutputService.errorStream).thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceOutputService.dispose()).thenReturn(null);

    sl.registerFactory<AgentCubit>(() => mockAgentCubit);
    sl.registerFactory<SettingsCubit>(() => mockSettingsCubit);
    sl.registerLazySingleton<VoiceInputServiceBase>(() => mockVoiceService);
    sl.registerLazySingleton<VoiceOutputServiceBase>(() => mockVoiceOutputService);
  });

  tearDown(() async {
    await sl.reset();
  });

  tearDownAll(() async {
    await stateController.close();
    await transcriptionController.close();
    await soundLevelController.close();
    await statusController.close();
    await errorController.close();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: ChatScreen(voiceInputService: mockVoiceService),
    );
  }

  group('ChatScreen - Voice Input Controls & Modes', () {
    testWidgets('renders mic button in input bar', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_mic_button')), findsOneWidget);
    });

    testWidgets(
        'Tap-to-talk mode: tapping mic starts listening and displays waveform visualizer',
        (tester) async {
      when(() => mockVoiceService.startListening(
            listenFor: any(named: 'listenFor'),
          )).thenAnswer((_) async => const Right(unit));
      when(() => mockVoiceService.stopListening())
          .thenAnswer((_) async => const Right('Halo Flames'));

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_mic_button')));
      await tester.pump();

      verify(() => mockVoiceService.startListening()).called(1);
      expect(find.byKey(const Key('voice_waveform_container')), findsOneWidget);

      // Simulate sending transcription
      await tester.tap(find.byKey(const Key('voice_waveform_send_button')));
      await tester.pump();

      verify(() => mockVoiceService.stopListening()).called(1);
      verify(() => mockAgentCubit.sendMessage('Halo Flames')).called(1);
      expect(find.byKey(const Key('voice_waveform_container')), findsNothing);
    });

    testWidgets(
        'Hold-to-speak mode: long press starts recording and release auto-dispatches text',
        (tester) async {
      when(() => mockVoiceService.startListening(
            listenFor: any(named: 'listenFor'),
          )).thenAnswer((_) async => const Right(unit));
      when(() => mockVoiceService.stopListening())
          .thenAnswer((_) async => const Right('Periksa cuaca hari ini'));

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('chat_mic_button'))),
      );
      // Advance by kLongPressTimeout
      await tester.pump(const Duration(milliseconds: 600));

      verify(() => mockVoiceService.startListening()).called(1);
      expect(find.byKey(const Key('voice_waveform_container')), findsOneWidget);

      await gesture.up();
      await tester.pump();

      verify(() => mockVoiceService.stopListening()).called(1);
      verify(() => mockAgentCubit.sendMessage('Periksa cuaca hari ini')).called(1);
      expect(find.byKey(const Key('voice_waveform_container')), findsNothing);
    });

    testWidgets(
        'Shows SnackBar error when microphone permission denied',
        (tester) async {
      when(() => mockVoiceService.startListening(
            listenFor: any(named: 'listenFor'),
          )).thenAnswer(
        (_) async => const Left(
          PermissionFailure('Microphone access denied. Please enable in settings.'),
        ),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_mic_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        find.text('Microphone access denied. Please enable in settings.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('voice_waveform_container')), findsNothing);
    });

    testWidgets(
        'Shows SnackBar error and cancels recording when errorStream emits error',
        (tester) async {
      when(() => mockVoiceService.startListening(
            listenFor: any(named: 'listenFor'),
          )).thenAnswer((_) async => const Right(unit));

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_mic_button')));
      await tester.pump();

      expect(find.byKey(const Key('voice_waveform_container')), findsOneWidget);

      errorController.add('Hardware microphone error');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Hardware microphone error'), findsOneWidget);
      expect(find.byKey(const Key('voice_waveform_container')), findsNothing);
    });
  });
}
