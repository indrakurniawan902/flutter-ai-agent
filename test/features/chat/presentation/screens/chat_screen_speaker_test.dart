import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/di/injection_container.dart';
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
  late MockVoiceInputService mockVoiceInputService;
  late MockVoiceOutputService mockVoiceOutputService;

  late StreamController<AgentState> agentStateController;
  late StreamController<VoiceInputStatus> voiceInputStatusController;
  late StreamController<VoiceOutputStatus> voiceOutputStatusController;

  setUp(() async {
    await sl.reset();

    mockAgentCubit = MockAgentCubit();
    mockSettingsCubit = MockSettingsCubit();
    mockVoiceInputService = MockVoiceInputService();
    mockVoiceOutputService = MockVoiceOutputService();

    agentStateController = StreamController<AgentState>.broadcast();
    voiceInputStatusController = StreamController<VoiceInputStatus>.broadcast();
    voiceOutputStatusController = StreamController<VoiceOutputStatus>.broadcast();

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.messages).thenReturn([]);
    when(() => mockAgentCubit.stream).thenAnswer((_) => agentStateController.stream);
    when(() => mockAgentCubit.sendMessage(any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.reset()).thenAnswer((_) async {});

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsLoaded(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o',
        temperature: 0.7,
      ),
    );
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockVoiceInputService.transcriptionStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceInputService.soundLevelStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceInputService.statusStream)
        .thenAnswer((_) => voiceInputStatusController.stream);
    when(() => mockVoiceInputService.errorStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceInputService.lastRecognizedWords).thenReturn('');
    when(() => mockVoiceInputService.isListening).thenReturn(false);
    when(() => mockVoiceInputService.isAvailable).thenReturn(true);
    when(() => mockVoiceInputService.dispose()).thenReturn(null);
    when(() => mockVoiceInputService.cancelListening()).thenAnswer((_) async {});
    when(() => mockVoiceInputService.stopListening())
        .thenAnswer((_) async => const Right(''));
    when(() => mockVoiceInputService.startListening(
          listenFor: any(named: 'listenFor'),
          pauseFor: any(named: 'pauseFor'),
          localeId: any(named: 'localeId'),
        )).thenAnswer((_) async => const Right(unit));

    bool isMuted = false;
    when(() => mockVoiceOutputService.isMuted).thenAnswer((_) => isMuted);
    when(() => mockVoiceOutputService.statusStream)
        .thenAnswer((_) => voiceOutputStatusController.stream);
    when(() => mockVoiceOutputService.errorStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceOutputService.toggleMute()).thenAnswer((_) {
      isMuted = !isMuted;
    });
    when(() => mockVoiceOutputService.setMuted(any())).thenAnswer((inv) {
      isMuted = inv.positionalArguments[0] as bool;
    });
    when(() => mockVoiceOutputService.interrupt()).thenAnswer((_) async {});
    when(() => mockVoiceOutputService.speakText(
          any(),
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        )).thenAnswer((_) async => const Right(unit));
    when(() => mockVoiceOutputService.dispose()).thenReturn(null);

    sl.registerFactory<AgentCubit>(() => mockAgentCubit);
    sl.registerFactory<SettingsCubit>(() => mockSettingsCubit);
    sl.registerLazySingleton<VoiceInputServiceBase>(() => mockVoiceInputService);
    sl.registerLazySingleton<VoiceOutputServiceBase>(() => mockVoiceOutputService);
  });

  tearDown(() async {
    await agentStateController.close();
    await voiceInputStatusController.close();
    await voiceOutputStatusController.close();
    await sl.reset();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: ChatScreen(
        voiceInputService: mockVoiceInputService,
        voiceOutputService: mockVoiceOutputService,
      ),
    );
  }

  group('ChatScreen - Speaker Mute/Unmute & Barge-in', () {
    testWidgets('renders speaker toggle button in AppBar with volume_up icon',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final speakerButton = find.byKey(const Key('chat_speaker_toggle'));
      expect(speakerButton, findsOneWidget);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
    });

    testWidgets('tapping speaker toggle toggles mute and updates icon',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final speakerButton = find.byKey(const Key('chat_speaker_toggle'));

      // Tap to mute
      await tester.tap(speakerButton);
      await tester.pumpAndSettle();

      verify(() => mockVoiceOutputService.toggleMute()).called(1);
      expect(find.byIcon(Icons.volume_off), findsOneWidget);

      // Tap again to unmute
      await tester.tap(speakerButton);
      await tester.pumpAndSettle();

      verify(() => mockVoiceOutputService.toggleMute()).called(1);
      expect(find.byIcon(Icons.volume_up), findsOneWidget);
    });

    testWidgets('barge-in: tapping mic button immediately interrupts audio playback',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final micButton = find.byKey(const Key('chat_mic_button'));
      expect(micButton, findsOneWidget);

      await tester.tap(micButton);
      await tester.pump();

      verify(() => mockVoiceOutputService.interrupt()).called(1);
    });

    testWidgets('agent response automatically calls speakText when speaker is unmuted',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      agentStateController.add(const AgentSuccess('Halo, ada yang bisa dibantu?'));
      await tester.pumpAndSettle();

      verify(() => mockVoiceOutputService.speakText('Halo, ada yang bisa dibantu?'))
          .called(1);
    });

    testWidgets('agent response does not call speakText when speaker is muted',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final speakerButton = find.byKey(const Key('chat_speaker_toggle'));
      await tester.tap(speakerButton); // Mute
      await tester.pumpAndSettle();

      agentStateController.add(const AgentSuccess('Silent response'));
      await tester.pumpAndSettle();

      verifyNever(() => mockVoiceOutputService.speakText(any()));
    });
  });
}
