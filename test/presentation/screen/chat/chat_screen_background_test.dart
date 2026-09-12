import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockAgentCubit mockAgentCubit;
  late MockVoiceInputService mockVoiceInputService;
  late MockVoiceOutputService mockVoiceOutputService;
  late MockBackgroundService mockBackgroundService;

  late StreamController<AgentState> agentStateController;
  late StreamController<VoiceInputStatus> voiceInputStatusController;
  late StreamController<String> backgroundActionController;

  setUp(() async {
    await sl.reset();

    mockAgentCubit = MockAgentCubit();
    mockVoiceInputService = MockVoiceInputService();
    mockVoiceOutputService = MockVoiceOutputService();
    mockBackgroundService = MockBackgroundService();

    agentStateController = StreamController<AgentState>.broadcast();
    voiceInputStatusController =
        StreamController<VoiceInputStatus>.broadcast();
    backgroundActionController = StreamController<String>.broadcast();

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.messages).thenReturn([]);
    when(
      () => mockAgentCubit.stream,
    ).thenAnswer((_) => agentStateController.stream);
    when(() => mockAgentCubit.sendMessage(any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.reset()).thenReturn(null);

    when(
      () => mockVoiceInputService.transcriptionStream,
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => mockVoiceInputService.soundLevelStream,
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => mockVoiceInputService.statusStream,
    ).thenAnswer((_) => voiceInputStatusController.stream);
    when(
      () => mockVoiceInputService.errorStream,
    ).thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceInputService.lastRecognizedWords).thenReturn('');
    when(() => mockVoiceInputService.isListening).thenReturn(false);
    when(() => mockVoiceInputService.isAvailable).thenReturn(true);
    when(
      () => mockVoiceInputService.startListening(),
    ).thenAnswer((_) async => const Right(unit));
    when(
      () => mockVoiceInputService.stopListening(),
    ).thenAnswer((_) async => const Right(''));
    when(
      () => mockVoiceInputService.cancelListening(),
    ).thenAnswer((_) async {});
    when(() => mockVoiceInputService.dispose()).thenReturn(null);

    when(() => mockVoiceOutputService.isMuted).thenReturn(false);
    when(
      () => mockVoiceOutputService.statusStream,
    ).thenAnswer((_) => const Stream.empty());
    when(
      () => mockVoiceOutputService.errorStream,
    ).thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceOutputService.interrupt()).thenAnswer((_) async {});
    when(() => mockVoiceOutputService.dispose()).thenReturn(null);

    when(
      () => mockBackgroundService.actionStream,
    ).thenAnswer((_) => backgroundActionController.stream);
    when(
      () => mockBackgroundService.getPendingAction(),
    ).thenAnswer((_) async => null);
    when(
      () => mockBackgroundService.clearPendingAction(),
    ).thenAnswer((_) async {});
    when(() => mockBackgroundService.dispose()).thenReturn(null);

    sl.registerFactory<AgentCubit>(() => mockAgentCubit);
  });

  tearDown(() async {
    await agentStateController.close();
    await voiceInputStatusController.close();
    await backgroundActionController.close();
    await sl.reset();
  });

  Widget createWidgetUnderTest({String? initialPendingAction}) {
    if (initialPendingAction != null) {
      when(
        () => mockBackgroundService.getPendingAction(),
      ).thenAnswer((_) async => initialPendingAction);
    }

    return MaterialApp(
      home: ChatScreen(
        voiceInputService: mockVoiceInputService,
        voiceOutputService: mockVoiceOutputService,
        backgroundService: mockBackgroundService,
      ),
    );
  }

  testWidgets(
      'ChatScreen listens to backgroundActionStream and starts voice input on "voice_input"',
      (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    backgroundActionController.add('voice_input');
    await tester.pump();

    verify(() => mockVoiceInputService.startListening()).called(1);
  });

  testWidgets(
      'ChatScreen listens to backgroundActionStream and sends status check on "quick_status"',
      (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    backgroundActionController.add('quick_status');
    await tester.pump();

    verify(
      () => mockAgentCubit.sendMessage(any(that: contains('status'))),
    ).called(1);
  });

  testWidgets('ChatScreen handles pendingAction on startup and clears it',
      (tester) async {
    await tester.pumpWidget(
      createWidgetUnderTest(initialPendingAction: 'voice_input'),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    verify(() => mockBackgroundService.getPendingAction()).called(1);
    verify(() => mockVoiceInputService.startListening()).called(1);
    verify(() => mockBackgroundService.clearPendingAction()).called(1);
  });
}
