import 'package:equatable/equatable.dart';

import 'package:flutter_ai_agent/domain/entities/share/shared_payload.dart';

/// Base state for [ShareTargetCubit].
sealed class ShareTargetState extends Equatable {
  const ShareTargetState();

  @override
  List<Object?> get props => [];
}

/// No share listening started yet.
class ShareTargetInitial extends ShareTargetState {
  const ShareTargetInitial();
}

/// Actively listening for OS share intents, no pending payload.
class ShareTargetListening extends ShareTargetState {
  const ShareTargetListening();
}

/// A batch of shared payloads arrived with a suggested chat prompt.
class ShareTargetReceived extends ShareTargetState {
  final List<SharedPayload> payloads;
  final String suggestedPrompt;

  const ShareTargetReceived({
    required this.payloads,
    required this.suggestedPrompt,
  });

  @override
  List<Object?> get props => [payloads, suggestedPrompt];
}

/// Share intake failed.
class ShareTargetError extends ShareTargetState {
  final String message;

  const ShareTargetError(this.message);

  @override
  List<Object?> get props => [message];
}
