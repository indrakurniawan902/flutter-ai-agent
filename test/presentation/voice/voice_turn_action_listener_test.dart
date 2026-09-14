import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_turn_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/overlay_bubble_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/voice/voice_turn_action_listener.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

class MockOverlayBubbleService extends Mock
    implements OverlayBubbleServiceBase {}

class _RecordingDispatcher implements VoicePromptDispatcherBase {
  final List<String> dispatched = [];

  @override
  String get transportId => 'fake';

  @override
  bool get isReady => true;

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
  late MockOverlayBubbleService mockOverlay;
  late MockAgentCubit mockAgentCubit;
  late VoicePromptDispatcherRegistry registry;
  late StreamController<String> actionController;
  late StreamController<VoiceTurnPhase> phaseController;

  const turnResult = VoiceTurnResult(
    transcript: 'hi',
    reply: 'hello',
    spoken: false,
    transportId: 'headless',
  );

  setUp(() {
    mockBackgroundService = MockBackgroundService();
    mockVoiceTurnService = MockVoiceTurnService();
    mockOverlay = MockOverlayBubbleService();
    mockAgentCubit = MockAgentCubit();
    registry = VoicePromptDispatcherRegistry();
    actionController = StreamController<String>.broadcast();
    phaseController = StreamController<VoiceTurnPhase>.broadcast();

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
    when(() => mockVoiceTurnService.phase).thenReturn(VoiceTurnPhase.idle);
    when(() => mockVoiceTurnService.phaseStream)
        .thenAnswer((_) => phaseController.stream);
    when(() => mockVoiceTurnService.errorStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceTurnService.cancelTurn()).thenAnswer((_) async {});

    when(() => mockOverlay.isBubbleEnabled()).thenAnswer((_) async => false);
    when(() => mockOverlay.setBubbleEnabled(any()))
        .thenAnswer((_) async => true);
    when(() => mockOverlay.setRecording(any())).thenAnswer((_) async => true);

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.isClosed).thenReturn(false);
    when(() => mockAgentCubit.stream)
        .thenAnswer((_) => const Stream.empty());
  });

  tearDown(() async {
    await actionController.close();
    await phaseController.close();
  });

  Widget createWidgetUnderTest({
    OverlayBubbleServiceBase? overlayBubbleService,
  }) {
    return MaterialApp(
      home: VoiceTurnActionListener(
        backgroundService: mockBackgroundService,
        voiceTurnService: mockVoiceTurnService,
        overlayBubbleService: overlayBubbleService,
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

  testWidgets('phase stream mirrors the recording state onto the bubble',
      (tester) async {
    // Arrange
    final order = <String>[];
    when(() => mockOverlay.setRecording(any())).thenAnswer((invocation) async {
      final recording = invocation.positionalArguments.first as bool;
      order.add(recording ? 'true' : 'false');
      return true;
    });
    await tester.pumpWidget(
      createWidgetUnderTest(overlayBubbleService: mockOverlay),
    );
    await tester.pump();

    // Act
    phaseController.add(VoiceTurnPhase.listening);
    await tester.pump();
    phaseController.add(VoiceTurnPhase.done);
    await tester.pump();

    // Assert
    verify(() => mockOverlay.setRecording(true)).called(1);
    verify(() => mockOverlay.setRecording(false)).called(1);
    expect(order, ['true', 'false']);
  });

  testWidgets('error phase clears the bubble recording indicator',
      (tester) async {
    // Arrange
    await tester.pumpWidget(
      createWidgetUnderTest(overlayBubbleService: mockOverlay),
    );
    await tester.pump();

    // Act
    phaseController.add(VoiceTurnPhase.error);
    await tester.pump();

    // Assert
    verify(() => mockOverlay.setRecording(false)).called(1);
    verifyNever(() => mockOverlay.setRecording(true));
  });

  testWidgets('a throwing setRecording never breaks the listener',
      (tester) async {
    // Arrange
    when(() => mockOverlay.setRecording(any()))
        .thenThrow(StateError('overlay down'));
    await tester.pumpWidget(
      createWidgetUnderTest(overlayBubbleService: mockOverlay),
    );
    await tester.pump();

    // Act
    phaseController.add(VoiceTurnPhase.listening);
    await tester.pump();
    phaseController.add(VoiceTurnPhase.done);
    await tester.pump();

    // Assert
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancel_voice cancels the turn and never starts one',
      (tester) async {
    // Arrange
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    // Act
    actionController.add('cancel_voice');
    await tester.pump();

    // Assert
    verify(() => mockVoiceTurnService.cancelTurn()).called(1);
    verifyNever(() => mockVoiceTurnService.runTurn());
  });

  testWidgets('quick_status never touches the overlay bubble',
      (tester) async {
    // Arrange
    final recorder = _RecordingDispatcher();
    await tester.pumpWidget(
      createWidgetUnderTest(overlayBubbleService: mockOverlay),
    );
    await tester.pump();
    registry.register(recorder);

    // Act
    actionController.add('quick_status');
    await tester.pump();

    // Assert
    expect(recorder.dispatched, hasLength(1));
    verifyNever(() => mockOverlay.setRecording(any()));
  });

  testWidgets('phase events without any overlay service do not throw',
      (tester) async {
    // Arrange
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    // Act
    phaseController.add(VoiceTurnPhase.listening);
    await tester.pump();
    phaseController.add(VoiceTurnPhase.done);
    await tester.pump();

    // Assert
    expect(tester.takeException(), isNull);
  });

  testWidgets('startup restores the persisted bubble when enabled',
      (tester) async {
    // Arrange
    when(() => mockOverlay.isBubbleEnabled()).thenAnswer((_) async => true);

    // Act
    await tester.pumpWidget(
      createWidgetUnderTest(overlayBubbleService: mockOverlay),
    );
    await tester.pump();
    await tester.pump();

    // Assert
    verify(() => mockOverlay.setBubbleEnabled(true)).called(1);
  });

  testWidgets('startup leaves the bubble off when the preference is false',
      (tester) async {
    // Act
    await tester.pumpWidget(
      createWidgetUnderTest(overlayBubbleService: mockOverlay),
    );
    await tester.pump();
    await tester.pump();

    // Assert
    verify(() => mockOverlay.isBubbleEnabled()).called(1);
    verifyNever(() => mockOverlay.setBubbleEnabled(any()));
  });
}
