import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
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
  late VoicePromptDispatcherRegistry registry;

  late StreamController<AgentState> agentStateController;
  late StreamController<VoiceInputStatus> voiceInputStatusController;

  setUp(() async {
    await sl.reset();

    mockAgentCubit = MockAgentCubit();
    mockVoiceInputService = MockVoiceInputService();
    mockVoiceOutputService = MockVoiceOutputService();
    registry = VoicePromptDispatcherRegistry();

    agentStateController = StreamController<AgentState>.broadcast();
    voiceInputStatusController =
        StreamController<VoiceInputStatus>.broadcast();

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.isClosed).thenReturn(false);
    when(() => mockAgentCubit.sessions).thenReturn(const []);
    when(() => mockAgentCubit.activeSessionId).thenReturn(null);
    when(() => mockAgentCubit.activeSessionTitle).thenReturn('New chat');
    when(() => mockAgentCubit.refreshSessions()).thenAnswer((_) async {});
    when(() => mockAgentCubit.newChat()).thenAnswer((_) async {});
    when(() => mockAgentCubit.switchSession(any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.renameSession(any(), any()))
        .thenAnswer((_) async {});
    when(() => mockAgentCubit.deleteSession(any())).thenAnswer((_) async {});
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

    sl.registerFactory<AgentCubit>(() => mockAgentCubit);
    sl.registerSingleton<VoicePromptDispatcherRegistry>(registry);
  });

  tearDown(() async {
    await agentStateController.close();
    await voiceInputStatusController.close();
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

  testWidgets('ChatScreen registers its chat dispatcher on mount',
      (tester) async {
    // Act
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    // Assert
    expect(registry.active, isNotNull);
    expect(registry.active!.transportId, 'chat');
  });

  testWidgets('ChatScreen unregisters its chat dispatcher on dispose',
      (tester) async {
    // Arrange
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();
    expect(registry.active, isNotNull);

    // Act
    await tester.pumpWidget(const SizedBox());

    // Assert
    expect(registry.hasReadyTransport, isFalse);
    expect(registry.active, isNull);
  });

  testWidgets(
      'a mounted ChatScreen owns a READY chat transport until it unmounts',
      (tester) async {
    // Act: mount the screen.
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    // Assert: the registry sees a ready transport registered by the screen.
    final mounted = registry.active;
    expect(mounted, isNotNull);
    final transport = mounted!;
    expect(transport.isReady, isTrue);
    expect(transport.transportId, 'chat');
    expect(registry.hasReadyTransport, isTrue);

    // Act: unmount the screen.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();

    // Assert: the transport is gone, so the headless fallback can take over.
    expect(registry.active, isNull);
    expect(registry.hasReadyTransport, isFalse);
  });
}
