import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';

abstract class SpeechToTextWrapper {
  bool get isAvailable;
  bool get isListening;
  String get lastRecognizedWords;
  Future<bool> hasPermission();
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
  });
  Future<void> listen({
    SpeechResultListener? onResult,
    SpeechSoundLevelChange? onSoundLevelChange,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
  });
  Future<void> stop();
  Future<void> cancel();
}

class DefaultSpeechToTextWrapper implements SpeechToTextWrapper {
  DefaultSpeechToTextWrapper({SpeechToText? speech})
      : _speech = speech ?? SpeechToText();

  final SpeechToText _speech;

  @override
  bool get isAvailable => _speech.isAvailable;

  @override
  bool get isListening => _speech.isListening;

  @override
  String get lastRecognizedWords => _speech.lastRecognizedWords;

  @override
  Future<bool> hasPermission() => _speech.hasPermission;

  @override
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
  }) =>
      _speech.initialize(onError: onError, onStatus: onStatus);

  @override
  Future<void> listen({
    SpeechResultListener? onResult,
    SpeechSoundLevelChange? onSoundLevelChange,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
  }) =>
      _speech.listen(
        onResult: onResult,
        onSoundLevelChange: onSoundLevelChange,
        listenOptions: SpeechListenOptions(
          listenFor: listenFor,
          pauseFor: pauseFor,
          localeId: localeId,
        ),
      );

  @override
  Future<void> stop() => _speech.stop();

  @override
  Future<void> cancel() => _speech.cancel();
}

@LazySingleton(as: VoiceInputServiceBase)
class VoiceInputService implements VoiceInputServiceBase {
  VoiceInputService({SpeechToTextWrapper? speech})
      : _speech = speech ?? DefaultSpeechToTextWrapper();

  @factoryMethod
  factory VoiceInputService.create() => VoiceInputService();

  static const String recognitionUnavailableMessage =
      'Speech recognition unavailable or voice pack missing on this device';

  final SpeechToTextWrapper _speech;

  final _transcriptionController = StreamController<String>.broadcast();
  final _soundLevelController = StreamController<double>.broadcast();
  final _statusController = StreamController<VoiceInputStatus>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  bool _listening = false;
  String _lastWords = '';

  static double normalizeSoundLevel(double raw) {
    if (raw.isNaN || raw.isInfinite) return 0.0;
    return raw.clamp(0.0, 1.0);
  }

  @override
  bool get isListening => _listening;

  @override
  bool get isAvailable => _speech.isAvailable;

  @override
  Stream<String> get transcriptionStream => _transcriptionController.stream;

  @override
  Stream<double> get soundLevelStream => _soundLevelController.stream;

  @override
  Stream<VoiceInputStatus> get statusStream => _statusController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  String get lastRecognizedWords => _lastWords;

  @override
  Future<Either<Failure, bool>> checkPermission() async {
    try {
      if (!_speech.isAvailable) {
        final ready = await _speech.initialize(
          onError: _onError,
          onStatus: _onStatus,
        );
        if (!ready) {
          return const Right(false);
        }
      }
      return Right(await _speech.hasPermission());
    } catch (e) {
      return Left(
        PermissionFailure(
          FailureMessage.humanize(
            e,
            context: 'Microphone permission check failed',
          ),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, bool>> initialize() async {
    try {
      final ready = await _speech.initialize(
        onError: _onError,
        onStatus: _onStatus,
      );
      return Right(ready);
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Speech initialization failed'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, Unit>> startListening({
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
  }) async {
    try {
      if (!_speech.isAvailable) {
        final ready = await _speech.initialize(
          onError: _onError,
          onStatus: _onStatus,
        );
        if (!ready) {
          _listening = false;
          bool hasPerm = false;
          try {
            hasPerm = await _speech.hasPermission();
          } catch (_) {
            hasPerm = false;
          }
          if (!hasPerm) {
            return const Left(
              PermissionFailure('Microphone permission denied'),
            );
          }
          return const Left(
            ServerFailure(recognitionUnavailableMessage),
          );
        }
      }
      await _speech.listen(
        onResult: _onResult,
        onSoundLevelChange: _onSoundLevel,
        listenFor: listenFor,
        pauseFor: pauseFor,
        localeId: localeId,
      );
      _listening = true;
      _emitStatus(VoiceInputStatus.listening);
      return const Right(unit);
    } catch (e) {
      _listening = false;
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Start listening failed'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, String>> stopListening() async {
    try {
      await _speech.stop();
      _listening = false;
      _emitStatus(VoiceInputStatus.done);
      final pluginWords = _speech.lastRecognizedWords;
      if (pluginWords.isNotEmpty) _lastWords = pluginWords;
      return Right(_lastWords);
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Stop listening failed'),
        ),
      );
    }
  }

  @override
  Future<void> cancelListening() async {
    try {
      await _speech.cancel();
    } finally {
      _listening = false;
      _emitStatus(VoiceInputStatus.idle);
    }
  }

  @override
  void dispose() {
    unawaited(_speech.cancel());
    _transcriptionController.close();
    _soundLevelController.close();
    _statusController.close();
    _errorController.close();
  }

  void _onResult(SpeechRecognitionResult result) {
    _lastWords = result.recognizedWords;
    if (!_transcriptionController.isClosed) {
      _transcriptionController.add(_lastWords);
    }
  }

  void _onSoundLevel(double level) {
    if (!_soundLevelController.isClosed) {
      _soundLevelController.add(normalizeSoundLevel(level));
    }
  }

  void _onStatus(String status) {
    switch (status) {
      case 'listening':
        _listening = true;
        _emitStatus(VoiceInputStatus.listening);
      case 'done':
        _listening = false;
        _emitStatus(VoiceInputStatus.done);
      case 'notListening':
        _listening = false;
        _emitStatus(VoiceInputStatus.idle);
      default:
        _emitStatus(VoiceInputStatus.idle);
    }
  }

  void _onError(SpeechRecognitionError error) {
    _listening = false;
    if (!_errorController.isClosed) {
      _errorController.add(error.errorMsg);
    }
    _emitStatus(VoiceInputStatus.error);
  }

  void _emitStatus(VoiceInputStatus status) {
    if (!_statusController.isClosed) _statusController.add(status);
  }
}
