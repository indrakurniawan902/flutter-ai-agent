import 'dart:async';

import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_mode.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/services/voice/gateway_voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';

/// Prompt transport owned by the chat surface.
///
/// Wraps the LIVE [AgentCubit] / gateway client instead of resolving them at
/// construction time, so a mounted ChatScreen keeps the open conversation in
/// sync, while the headless fallback still works when no screen exists.
class ChatVoicePromptDispatcher implements VoicePromptDispatcherBase {
  ChatVoicePromptDispatcher({
    required AgentCubit? Function() resolveCubit,
    required GatewayClientBase? Function() resolveGatewayClient,
    ChatMode Function()? mode,
    String transportId = 'chat',
    this.dispatchTimeout = const Duration(seconds: 120),
  })  : _resolveCubit = resolveCubit,
        _resolveGatewayClient = resolveGatewayClient,
        _mode = mode,
        _transportId = transportId;

  final AgentCubit? Function() _resolveCubit;
  final GatewayClientBase? Function() _resolveGatewayClient;
  final ChatMode Function()? _mode;
  final String _transportId;

  /// Test-visible timeout for the direct-path terminal-state wait.
  final Duration dispatchTimeout;

  @override
  String get transportId => _transportId;

  /// Gateway wins only when explicitly selected or already connected, so a
  /// disconnected socket falls back to the local cubit instead of hanging.
  bool get _useGateway {
    final mode = _mode;
    if (mode != null) {
      return mode() == ChatMode.gateway;
    }
    return _resolveGatewayClient()?.state.isConnected == true;
  }

  @override
  bool get isReady {
    if (_useGateway) {
      final client = _resolveGatewayClient();
      return client != null && client.state.isConnected;
    }
    final cubit = _resolveCubit();
    if (cubit == null || cubit.isClosed) {
      return false;
    }
    return !_isBusy(cubit.state);
  }

  @override
  Future<Either<Failure, String>> dispatch(String prompt) async {
    final trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      return const Left(VoiceTurnEmptyFailure());
    }
    if (_useGateway) {
      final client = _resolveGatewayClient();
      if (client == null) {
        return const Left(VoiceTurnNoTransportFailure());
      }
      return GatewayVoicePromptDispatcher(client: client).dispatch(trimmed);
    }
    final cubit = _resolveCubit();
    if (cubit == null || cubit.isClosed) {
      return const Left(VoiceTurnNoTransportFailure());
    }
    if (_isBusy(cubit.state)) {
      return const Left(VoiceTurnBusyFailure());
    }
    // Subscribe before sending so the terminal state cannot be missed when
    // the agent answers synchronously.
    final terminal = cubit.stream.firstWhere(
      (s) => s is AgentSuccess || s is AgentError || s is WaitingApproval,
    );
    unawaited(cubit.sendMessage(trimmed));
    final AgentState state = await terminal.timeout(
      dispatchTimeout,
      onTimeout: () => cubit.state,
    );
    if (state is AgentSuccess) {
      return Right(state.response);
    }
    if (state is AgentError) {
      return Left(ServerFailure(state.message));
    }
    if (state is WaitingApproval) {
      return const Left(VoiceTurnNeedsApprovalFailure());
    }
    return const Left(
      ServerFailure('voice_turn_timeout: no reply from the agent'),
    );
  }

  @override
  Future<void> cancel() async {
    if (_useGateway) {
      final client = _resolveGatewayClient();
      if (client == null) {
        return;
      }
      await GatewayVoicePromptDispatcher(client: client).cancel();
      return;
    }
    await _resolveCubit()?.stop();
  }

  static bool _isBusy(AgentState state) {
    return state is AgentThinking ||
        state is AgentStreaming ||
        state is ExecutingTool ||
        state is WaitingApproval;
  }
}
