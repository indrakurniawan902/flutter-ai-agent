import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_turn_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';

@LazySingleton(as: VoiceTurnServiceBase)
class VoiceTurnService implements VoiceTurnServiceBase {
  VoiceTurnService({
    required VoiceInputServiceBase voiceInput,
    required VoiceOutputServiceBase voiceOutput,
    required VoicePromptDispatcherRegistry registry,
  })  : _voiceInput = voiceInput,
        _voiceOutput = voiceOutput,
        _registry = registry;

  @factoryMethod
  factory VoiceTurnService.create(
    VoiceInputServiceBase voiceInput,
    VoiceOutputServiceBase voiceOutput,
    VoicePromptDispatcherRegistry registry,
  ) =>
      VoiceTurnService(
        voiceInput: voiceInput,
        voiceOutput: voiceOutput,
        registry: registry,
      );

  static const defaultListenFor = Duration(seconds: 15);
  static const defaultPauseFor = Duration(seconds: 3);
  static const transcriptGracePeriod = Duration(seconds: 2);

  final VoiceInputServiceBase _voiceInput;
  final VoiceOutputServiceBase _voiceOutput;
  final VoicePromptDispatcherRegistry _registry;

  bool _active = false;
  VoiceTurnPhase _phase = VoiceTurnPhase.idle;
  final _phaseController = StreamController<VoiceTurnPhase>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  @override
  bool get isTurnActive => _active;

  @override
  VoiceTurnPhase get phase => _phase;

  @override
  Stream<VoiceTurnPhase> get phaseStream => _phaseController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  Future<Either<Failure, VoiceTurnResult>> runTurn({
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
  }) async {
    if (_active) {
      return const Left(VoiceTurnBusyFailure());
    }
    _active = true;
    _emitPhase(VoiceTurnPhase.listening);
    try {
      // A missing transport must never open the microphone.
      final dispatcher = _registry.active;
      if (dispatcher == null) {
        const failure = VoiceTurnNoTransportFailure();
        _emitPhase(VoiceTurnPhase.error);
        _pushError(failure.message);
        return const Left(failure);
      }

      final permission = await _voiceInput.checkPermission();
      final Failure? permissionFailure = permission.fold(
        (failure) => failure,
        (granted) => granted
            ? null
            : const PermissionFailure('Microphone permission denied'),
      );
      if (permissionFailure != null) {
        _emitPhase(VoiceTurnPhase.error);
        _pushError(permissionFailure.message);
        return Left(permissionFailure);
      }

      // Never record over a playing answer.
      await _voiceOutput.interrupt();

      final ready = await _voiceInput.initialize();
      final Failure? initFailure = ready.fold(
        (failure) => failure,
        (available) => available
            ? null
            : const ServerFailure(
                'voice_turn_stt_unavailable: '
                'speech recognition is unavailable on this device',
              ),
      );
      if (initFailure != null) {
        _emitPhase(VoiceTurnPhase.error);
        _pushError(initFailure.message);
        return Left(initFailure);
      }

      final effectiveListenFor = listenFor ?? defaultListenFor;
      final effectivePauseFor = pauseFor ?? defaultPauseFor;
      final started = await _voiceInput.startListening(
        listenFor: effectiveListenFor,
        pauseFor: effectivePauseFor,
        localeId: localeId,
      );
      final Failure? startFailure = started.fold(
        (failure) => failure,
        (_) => null,
      );
      if (startFailure != null) {
        _emitPhase(VoiceTurnPhase.error);
        _pushError(startFailure.message);
        return Left(startFailure);
      }

      final transcriptResult = await _awaitTranscript(effectiveListenFor);
      final String? recognized = transcriptResult.fold(
        (failure) {
          _emitPhase(VoiceTurnPhase.error);
          _pushError(failure.message);
          return null;
        },
        (text) => text,
      );
      if (recognized == null) {
        return Left(
          transcriptResult.fold(
            (failure) => failure,
            (_) => const ServerFailure('voice_turn_stt_error'),
          ),
        );
      }

      final transcript = recognized.trim();
      if (transcript.isEmpty) {
        _emitPhase(VoiceTurnPhase.done);
        return const Left(VoiceTurnEmptyFailure());
      }

      _emitPhase(VoiceTurnPhase.dispatching);
      final reply = await dispatcher.dispatch(transcript);
      final String? replyText = reply.fold(
        (failure) {
          _emitPhase(VoiceTurnPhase.error);
          _pushError(failure.message);
          return null;
        },
        (text) => text.trim(),
      );
      if (replyText == null) {
        return Left(
          reply.fold(
            (failure) => failure,
            (_) => const ServerFailure('voice_turn_dispatch_failed'),
          ),
        );
      }

      var spoken = false;
      if (!_voiceOutput.isMuted && replyText.isNotEmpty) {
        _emitPhase(VoiceTurnPhase.speaking);
        final speakResult = await _voiceOutput.speakText(replyText);
        spoken = speakResult.isRight();
      }

      _emitPhase(VoiceTurnPhase.done);
      return Right(
        VoiceTurnResult(
          transcript: transcript,
          reply: replyText.isEmpty ? null : replyText,
          spoken: spoken,
          transportId: dispatcher.transportId,
        ),
      );
    } finally {
      _active = false;
    }
  }

  @override
  Future<void> cancelTurn() async {
    if (!_active) {
      return;
    }
    await _voiceInput.cancelListening();
    await _registry.active?.cancel();
    _active = false;
    _emitPhase(VoiceTurnPhase.idle);
  }

  @override
  void dispose() {
    unawaited(cancelTurn());
    if (!_phaseController.isClosed) {
      _phaseController.close();
    }
    if (!_errorController.isClosed) {
      _errorController.close();
    }
  }

  // Guard timer keeps a silent recognizer from hanging the turn forever.
  Future<Either<Failure, String>> _awaitTranscript(Duration listenFor) async {
    String? lastError;
    final completer = Completer<bool>();
    StreamSubscription<VoiceInputStatus>? statusSub;
    StreamSubscription<String>? errorSub;
    Timer? guard;
    late final Either<Failure, String> outcome;
    try {
      statusSub = _voiceInput.statusStream.listen((status) {
        if (completer.isCompleted) {
          return;
        }
        if (status == VoiceInputStatus.done) {
          completer.complete(true);
        } else if (status == VoiceInputStatus.error) {
          completer.complete(false);
        }
      });
      errorSub = _voiceInput.errorStream.listen((message) {
        lastError = message;
      });
      guard = Timer(
        listenFor + defaultPauseFor + transcriptGracePeriod,
        () {
          if (!completer.isCompleted) {
            completer.complete(true);
          }
        },
      );
      final succeeded = await completer.future;
      if (succeeded) {
        final stopped = await _voiceInput.stopListening();
        outcome = stopped.fold(
          (failure) => Left<Failure, String>(failure),
          (text) => Right<Failure, String>(
            text.isNotEmpty ? text : _voiceInput.lastRecognizedWords,
          ),
        );
      } else {
        await _voiceInput.cancelListening();
        final detail = (lastError == null || lastError!.isEmpty)
            ? 'speech recognition failed'
            : lastError!;
        outcome = Left(ServerFailure('voice_turn_stt_error: $detail'));
      }
    } finally {
      guard?.cancel();
      await statusSub?.cancel();
      await errorSub?.cancel();
    }
    return outcome;
  }

  void _emitPhase(VoiceTurnPhase next) {
    _phase = next;
    if (!_phaseController.isClosed) {
      _phaseController.add(next);
    }
  }

  void _pushError(String message) {
    if (!_errorController.isClosed) {
      _errorController.add(message);
    }
  }
}
