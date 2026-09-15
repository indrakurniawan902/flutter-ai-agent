// Layer split pinned by this file.
//
// The Kotlin choke point MainActivity.extractActionFromIntent compares the
// `extra_flames_action` extra EXACTLY against `voice_input` / `cancel_voice` /
// `quick_status` and never normalizes, so case/whitespace variants drop there
// and never reach Dart. That layer is pinned natively by
// test/domain/tools/chat/main_activity_action_whitelist_contract_test.dart.
//
// This file pins the second, Dart-side layer: VoiceTurnActionListener's
// switch (action.toLowerCase().trim()) normalizes case and whitespace and then
// matches one of the three actions, dropping everything else. So if a variant
// ever escapes the Kotlin layer, Dart still recognizes it as whitelisted. Both
// behaviours are pinned: Kotlin drops the variants, Dart normalizes and matches
// them. Two layers, not a moved layer.

import 'dart:async';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_turn_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/overlay_bubble_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
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
    registerFallbackValue(QuickTileState.inactive);
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
    when(() => mockBackgroundService.setTileState(any()))
        .thenAnswer((_) async => const Right<Failure, bool>(true));

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

  Widget createWidgetUnderTest() {
    return MaterialApp(
      home: VoiceTurnActionListener(
        backgroundService: mockBackgroundService,
        voiceTurnService: mockVoiceTurnService,
        overlayBubbleService: mockOverlay,
        registry: registry,
        agentCubit: mockAgentCubit,
        child: const Text('no chat here'),
      ),
    );
  }

  testWidgets('a non-whitelist action dispatched on the stream is dropped',
      (tester) async {
    // Arrange
    final recorder = _RecordingDispatcher();
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();
    registry.register(recorder);

    // Act
    actionController.add('drop_the_agent');
    await tester.pump();
    await tester.pump();

    // Assert
    verifyNever(() => mockVoiceTurnService.runTurn());
    verifyNever(() => mockVoiceTurnService.cancelTurn());
    expect(recorder.dispatched, isEmpty);
    verifyNever(() => mockBackgroundService.setTileState(any()));
  });

  testWidgets('values that are not one of the three actions are dropped',
      (tester) async {
    // Arrange
    const rejected = [
      '',
      'voice__input',
      'quick-status',
      'drop_the_agent',
      'run shell',
      'quick_status_extra',
    ];

    for (final value in rejected) {
      final recorder = _RecordingDispatcher();
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pump();
      registry.register(recorder);

      // Act
      actionController.add(value);
      await tester.pump();
      await tester.pump();

      // Assert
      verifyNever(() => mockVoiceTurnService.runTurn());
      verifyNever(() => mockVoiceTurnService.cancelTurn());
      expect(
        recorder.dispatched,
        isEmpty,
        reason: 'value "$value" must not reach the dispatcher',
      );
      verifyNever(() => mockBackgroundService.setTileState(any()));

      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('the Dart layer normalizes case and whitespace before matching',
      (tester) async {
    // The Kotlin choke point compares exactly and drops these variants; the
    // Dart switch normalizes, so if a variant ever reaches Dart it is still
    // matched as one of the three whitelisted actions.
    // Arrange
    final recorder = _RecordingDispatcher();
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();
    registry.register(recorder);

    // Act
    actionController.add('QUICK_STATUS ');
    await tester.pump();
    await tester.pump();

    // Assert
    expect(recorder.dispatched, hasLength(1));
    expect(recorder.dispatched.single, contains('Quick status check'));
    verifyNever(() => mockVoiceTurnService.runTurn());

    // Act
    actionController.add(' Voice_Input');
    await tester.pump();
    await tester.pump();

    // Assert
    verify(() => mockVoiceTurnService.runTurn()).called(1);

    // Act
    actionController.add('Cancel_Voice');
    await tester.pump();
    await tester.pump();

    // Assert
    verify(() => mockVoiceTurnService.cancelTurn()).called(1);
  });

  testWidgets(
      'a non-whitelist pending action at startup does nothing but is still cleared',
      (tester) async {
    // Arrange
    when(() => mockBackgroundService.getPendingAction())
        .thenAnswer((_) async => 'drop_the_agent');
    final recorder = _RecordingDispatcher();

    // Act
    await tester.pumpWidget(createWidgetUnderTest());
    registry.register(recorder);
    await tester.pump();
    await tester.pump();

    // Assert
    verifyNever(() => mockVoiceTurnService.runTurn());
    verifyNever(() => mockVoiceTurnService.cancelTurn());
    expect(recorder.dispatched, isEmpty);
    verifyNever(() => mockBackgroundService.setTileState(any()));
    // The rejected value must not be left dangling for a later listener.
    verify(() => mockBackgroundService.clearPendingAction()).called(1);
  });

  testWidgets('voice_input on the stream still starts exactly one turn',
      (tester) async {
    // Arrange
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    // Act
    actionController.add('voice_input');
    await tester.pump();
    await tester.pump();

    // Assert
    verify(() => mockVoiceTurnService.runTurn()).called(1);
  });

  testWidgets('cancel_voice on the stream still cancels exactly one turn',
      (tester) async {
    // Arrange
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    // Act
    actionController.add('cancel_voice');
    await tester.pump();
    await tester.pump();

    // Assert
    verify(() => mockVoiceTurnService.cancelTurn()).called(1);
    verifyNever(() => mockVoiceTurnService.runTurn());
  });

  testWidgets('quick_status on the stream still dispatches the status prompt',
      (tester) async {
    // Arrange
    final recorder = _RecordingDispatcher();
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();
    registry.register(recorder);

    // Act
    actionController.add('quick_status');
    await tester.pump();
    await tester.pump();

    // Assert
    expect(recorder.dispatched, hasLength(1));
    expect(recorder.dispatched.single, contains('Quick status check'));
    verifyNever(() => mockVoiceTurnService.runTurn());
  });

  test('the Dart switch keeps all three actions as defense-in-depth', () {
    // The native Kotlin choke point validates the extra, but this switch must
    // not be removed on those grounds: two layers, not a moved layer. A future
    // native regression must not turn straight into a headless voice turn.
    final root = Directory.current.path;
    final file = File(
      '$root/lib/presentation/voice/voice_turn_action_listener.dart',
    );
    if (!file.existsSync()) {
      markTestSkipped('voice_turn_action_listener.dart not found');
      return;
    }
    final source = file.readAsStringSync();

    String bracedBlock(String anchor) {
      final start = source.indexOf(anchor);
      if (start < 0) fail('missing anchor: $anchor');
      final open = source.indexOf('{', start);
      var depth = 0;
      for (var i = open; i < source.length; i++) {
        if (source[i] == '{') depth++;
        if (source[i] == '}') {
          depth--;
          if (depth == 0) return source.substring(open, i + 1);
        }
      }
      fail('unbalanced braces after: $anchor');
    }

    final body = bracedBlock('void _handleAction(String action)');
    expect(body, contains('switch (action.toLowerCase().trim())'));
    expect(body, contains("case 'voice_input':"));
    expect(body, contains("case 'cancel_voice':"));
    expect(body, contains("case 'quick_status':"));
  });
}
