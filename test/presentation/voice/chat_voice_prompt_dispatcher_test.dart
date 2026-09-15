import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_mode.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_request.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/voice/chat_voice_prompt_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

void main() {
  setUpAll(() {
    registerFallbackValue('');
  });

  late MockAgentCubit mockAgentCubit;
  late MockGatewayClient mockGatewayClient;
  late StreamController<AgentState> stateController;
  late StreamController<GatewayMessage> messageController;

  setUp(() {
    mockAgentCubit = MockAgentCubit();
    mockGatewayClient = MockGatewayClient();
    stateController = StreamController<AgentState>.broadcast();
    messageController = StreamController<GatewayMessage>.broadcast();

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.isClosed).thenReturn(false);
    when(() => mockAgentCubit.stream)
        .thenAnswer((_) => stateController.stream);

    when(() => mockGatewayClient.state)
        .thenReturn(GatewayConnectionState.connected);
    when(() => mockGatewayClient.messageStream)
        .thenAnswer((_) => messageController.stream);
  });

  tearDown(() async {
    await stateController.close();
    await messageController.close();
  });

  ChatVoicePromptDispatcher directDispatcher() =>
      ChatVoicePromptDispatcher(
        resolveCubit: () => mockAgentCubit,
        resolveGatewayClient: () => null,
      );

  ChatVoicePromptDispatcher gatewayDispatcher() =>
      ChatVoicePromptDispatcher(
        resolveCubit: () => mockAgentCubit,
        resolveGatewayClient: () => mockGatewayClient,
        mode: () => ChatMode.gateway,
      );

  test('direct path resolves AgentSuccess response', () async {
    // Arrange
    when(() => mockAgentCubit.sendMessage(any())).thenAnswer((_) async {
      stateController.add(const AgentSuccess('hello'));
    });
    final dispatcher = directDispatcher();

    // Act
    final result = await dispatcher.dispatch('hi');

    // Assert
    expect(result, const Right<Failure, String>('hello'));
    verify(() => mockAgentCubit.sendMessage('hi')).called(1);
  });

  test('direct path maps AgentError to ServerFailure', () async {
    // Arrange
    when(() => mockAgentCubit.sendMessage(any())).thenAnswer((_) async {
      stateController.add(const AgentError('boom'));
    });
    final dispatcher = directDispatcher();

    // Act
    final result = await dispatcher.dispatch('hi');

    // Assert
    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) {
        expect(failure, isA<ServerFailure>());
        expect(failure.message, 'boom');
      },
      (_) => fail('expected Left'),
    );
  });

  test('direct path maps WaitingApproval to VoiceTurnNeedsApprovalFailure',
      () async {
    // Arrange
    const request = ToolCallRequest(
      id: 'call_1',
      name: 'send_notification',
      parameters: {'title': 'hi'},
    );
    when(() => mockAgentCubit.sendMessage(any())).thenAnswer((_) async {
      stateController.add(const WaitingApproval(request));
    });
    final dispatcher = directDispatcher();

    // Act
    final result = await dispatcher.dispatch('hi');

    // Assert
    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(failure, isA<VoiceTurnNeedsApprovalFailure>()),
      (_) => fail('expected Left'),
    );
  });

  test('direct path with busy cubit returns VoiceTurnBusyFailure', () async {
    // Arrange
    when(() => mockAgentCubit.state).thenReturn(const AgentThinking());
    final dispatcher = directDispatcher();

    // Act
    final result = await dispatcher.dispatch('hi');

    // Assert
    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(failure, isA<VoiceTurnBusyFailure>()),
      (_) => fail('expected Left'),
    );
    verifyNever(() => mockAgentCubit.sendMessage(any()));
  });

  test('absent cubit returns VoiceTurnNoTransportFailure', () async {
    // Arrange
    final dispatcher = ChatVoicePromptDispatcher(
      resolveCubit: () => null,
      resolveGatewayClient: () => null,
    );

    // Act
    final result = await dispatcher.dispatch('hi');

    // Assert
    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(failure, isA<VoiceTurnNoTransportFailure>()),
      (_) => fail('expected Left'),
    );
  });

  test('gateway path sends chat_message and resolves assistant reply',
      () async {
    // Arrange
    final dispatcher = gatewayDispatcher();
    expect(dispatcher.isReady, isTrue);

    // Act
    final future = dispatcher.dispatch('hi');
    await Future<void>.delayed(Duration.zero);
    messageController.add(
      const GatewayChatMessage(role: 'assistant', content: 'reply'),
    );
    final result = await future;

    // Assert
    expect(result, const Right<Failure, String>('reply'));
    verify(() => mockGatewayClient.sendChatMessage('hi')).called(1);
  });

  test('gateway path while disconnected is not ready and returns Left',
      () async {
    // Arrange
    when(() => mockGatewayClient.state)
        .thenReturn(GatewayConnectionState.disconnected);
    final dispatcher = gatewayDispatcher();

    // Act
    expect(dispatcher.isReady, isFalse);
    final result = await dispatcher.dispatch('hi');

    // Assert
    expect(result.isLeft(), isTrue);
    verifyNever(() => mockGatewayClient.sendChatMessage(any()));
  });

  test('gateway cancel aborts the in-flight dispatch', () async {
    // Arrange
    final dispatcher = gatewayDispatcher();

    // Act
    final future = dispatcher.dispatch('hi');
    await Future<void>.delayed(Duration.zero);
    await dispatcher.cancel();

    // Assert
    final result = await future;
    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(
        failure.message,
        'voice_turn_cancelled: voice turn cancelled',
      ),
      (_) => fail('expected Left'),
    );
    verify(() => mockGatewayClient.sendChatCancel()).called(1);
  });

  test('gateway single-flight rejects a concurrent dispatch', () async {
    // Arrange
    final dispatcher = gatewayDispatcher();

    // Act
    final first = dispatcher.dispatch('hi');
    await Future<void>.delayed(Duration.zero);
    final second = await dispatcher.dispatch('again');

    // Assert
    second.fold(
      (failure) => expect(failure, isA<VoiceTurnBusyFailure>()),
      (_) => fail('expected Left'),
    );
    verify(() => mockGatewayClient.sendChatMessage('hi')).called(1);
    verifyNever(() => mockGatewayClient.sendChatMessage('again'));

    // Act: finish the first dispatch.
    messageController.add(
      const GatewayChatMessage(role: 'assistant', content: 'reply'),
    );
    expect(await first, const Right<Failure, String>('reply'));
  });
}
