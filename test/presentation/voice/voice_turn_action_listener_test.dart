import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_turn_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/voice/voice_turn_action_listener.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

class _RecordingDispatcher implements VoicePromptDispatcherBase {
  final List<String> dispatched = [];

  @override
  String get transportId => 'fake';

  @override
  bool get isReady => true;

  @override
  bool get speaksReply => false;

  @override
  Future<Either<Failure, String>> dispatch(String prompt) async {
    dispatched.add(prompt);
    return const Right('ok');
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  late MockBackgroundService mockBackgroundService;
  late MockVoiceTurnService mockVoiceTurnService;
  late MockAgentCubit mockAgentCubit;
  late VoicePromptDispatcherRegistry registry;
  late StreamController<String> actionController;

  const turnResult = VoiceTurnResult(
    transcript: 'hi',
    reply: 'hello',
    spoken: false,
    transportId: 'headless',
  );

  setUp(() {
    mockBackgroundService = MockBackgroundService();
    mockVoiceTurnService = MockVoiceTurnService();
    mockAgentCubit = MockAgentCubit();
    registry = VoicePromptDispatcherRegistry();
    actionController = StreamController<String>.broadcast();

    when(() => mockBackgroundService.actionStream)
        .thenAnswer((_) => actionController.stream);
    when(() => mockBackgroundService.getPendingAction())
        .thenAnswer((_) async => null);
    when(() => mockBackgroundService.clearPendingAction())
        .thenAnswer((_) async {});
    when(() => mockBackgroundService.dispose()).thenReturn(null);

    when(() => mockVoiceTurnService.runTurn())
        .thenAnswer((_) async => const Right<Failure, VoiceTurnResult>(
              turnResult,
            ));
    when(() => mockVoiceTurnService.isTurnActive).thenReturn(false);
    when(() => mockVoiceTurnService.phase)
        .thenReturn(VoiceTurnPhase.idle);
    when(() => mockVoiceTurnService.phaseStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceTurnService.errorStream)
        .thenAnswer((_) => const Stream.empty());

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.isClosed).thenReturn(false);
    when(() => mockAgentCubit.stream)
        .thenAnswer((_) => const Stream.empty());
  });

  tearDown(() async {
    await actionController.close();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: VoiceTurnActionListener(
        backgroundService: mockBackgroundService,
        voiceTurnService: mockVoiceTurnService,
        registry: registry,
        agentCubit: mockAgentCubit,
        child: const Text('no chat here'),
      ),
    );
  }

  testWidgets('voice_input background action starts a voice turn',
      (tester) async {
    // Arrange
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();
    expect(find.text('no chat here'), findsOneWidget);

    // Act
    actionController.add('voice_input');
    await tester.pump();

    // Assert
    verify(() => mockVoiceTurnService.runTurn()).called(1);
    expect(find.byType(ChatScreen), findsNothing);
  });

  testWidgets('pending voice_input at startup triggers runTurn and clears it',
      (tester) async {
    // Arrange
    when(() => mockBackgroundService.getPendingAction())
        .thenAnswer((_) async => 'voice_input');

    // Act
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();
    await tester.pump();

    // Assert
    verify(() => mockVoiceTurnService.runTurn()).called(1);
    verify(() => mockBackgroundService.clearPendingAction()).called(1);
  });

  testWidgets('quick_status dispatches through the registry, not a turn',
      (tester) async {
    // Arrange
    final recorder = _RecordingDispatcher();
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();
    registry.register(recorder);

    // Act
    actionController.add('quick_status');
    await tester.pump();

    // Assert
    expect(recorder.dispatched, hasLength(1));
    expect(recorder.dispatched.single, contains('Quick status check'));
    verifyNever(() => mockVoiceTurnService.runTurn());
  });

  testWidgets('disposing the widget unsubscribes from actions',
      (tester) async {
    // Arrange
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    // Act
    await tester.pumpWidget(const SizedBox());
    actionController.add('voice_input');
    await tester.pump();

    // Assert
    verifyNever(() => mockVoiceTurnService.runTurn());
  });
}
