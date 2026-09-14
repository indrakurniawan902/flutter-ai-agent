import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';

import 'package:flutter_ai_agent/common/failure.dart';

/// Progress of a single headless voice turn.
enum VoiceTurnPhase { idle, listening, dispatching, speaking, done, error }

/// Outcome of one completed voice turn.
class VoiceTurnResult extends Equatable {
  final String transcript;
  final String? reply;
  final bool spoken;
  final String transportId;

  const VoiceTurnResult({
    required this.transcript,
    this.reply,
    this.spoken = false,
    required this.transportId,
  });

  @override
  List<Object?> get props => [transcript, reply, spoken, transportId];
}

/// Runs exactly ONE voice turn (listen -> STT -> dispatch -> TTS) with no
/// ChatScreen required. Implemented in `lib/data/services/voice/`.
abstract class VoiceTurnServiceBase {
  bool get isTurnActive;
  VoiceTurnPhase get phase;
  Stream<VoiceTurnPhase> get phaseStream;
  Stream<String> get errorStream;

  /// One shot: returns Left when the turn could not complete.
  Future<Either<Failure, VoiceTurnResult>> runTurn({
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
  });

  Future<void> cancelTurn();
  void dispose();
}
