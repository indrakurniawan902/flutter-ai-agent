import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';

/// Dispatches a voice transcript over the already-connected gateway WebSocket.
///
/// Reuses the existing `chat_message` frame (in) and the `chat_message
/// role=assistant` frame (out) that the bridge relay already speaks; no
/// protocol change is required.
@lazySingleton
class GatewayVoicePromptDispatcher implements VoicePromptDispatcherBase {
  static const dispatchTimeout = Duration(seconds: 120);

  final GatewayClientBase _client;
  Completer<Either<Failure, String>>? _inFlight;

  GatewayVoicePromptDispatcher({required GatewayClientBase client})
      : _client = client;

  @override
  String get transportId => 'gateway';

  // Gateway readiness mirrors the socket state, so a dropped socket
  // immediately yields the registry fallback instead of a hung dispatch.
  @override
  bool get isReady => _client.state.isConnected;

  /// Nothing else speaks a gateway reply, so the turn service owns the audio.
  @override
  bool get speaksReply => false;

  @override
  Future<Either<Failure, String>> dispatch(String prompt) async {
    final String trimmed = prompt.trim();
    if (trimmed.isEmpty) {
      return const Left(
        ServerFailure('voice_turn_empty: no speech was recognized'),
      );
    }
    if (!isReady) {
      return const Left(
        ConnectionFailure('voice_turn_no_transport: gateway is not connected'),
      );
    }
    if (_inFlight != null) {
      return const Left(VoiceTurnBusyFailure());
    }
    final Completer<Either<Failure, String>> completer =
        Completer<Either<Failure, String>>();
    _inFlight = completer;
    StreamSubscription<GatewayMessage>? messageSub;
    try {
      messageSub = _client.messageStream.listen((GatewayMessage message) {
        if (message is GatewayChatMessage &&
            message.role == 'assistant' &&
            message.content.isNotEmpty) {
          if (!completer.isCompleted) {
            completer.complete(Right<Failure, String>(message.content));
          }
        } else if (message is GatewayErrorMessage) {
          if (!completer.isCompleted) {
            completer.complete(
              Left<Failure, String>(ServerFailure(message.message)),
            );
          }
        }
      });
      _client.sendChatMessage(trimmed);
      final Either<Failure, String> result = await completer.future.timeout(
        dispatchTimeout,
        onTimeout: () {
          _client.sendChatCancel();
          return const Left<Failure, String>(
            ServerFailure('voice_turn_timeout: no reply from gateway'),
          );
        },
      );
      return result;
    } finally {
      await messageSub?.cancel();
      _inFlight = null;
    }
  }

  @override
  Future<void> cancel() async {
    final Completer<Either<Failure, String>>? pending = _inFlight;
    if (pending == null) {
      return;
    }
    // Abort server generation first so no late assistant frame lands
    // after the caller has moved on.
    _client.sendChatCancel();
    if (!pending.isCompleted) {
      pending.complete(
        const Left<Failure, String>(
          ServerFailure('voice_turn_cancelled: voice turn cancelled'),
        ),
      );
    }
  }
}
