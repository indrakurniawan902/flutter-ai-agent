import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Status of voice input recording and transcription.
enum VoiceInputStatus {
  idle,
  listening,
  done,
  error,
}

/// Abstract platform wrapper around SpeechToText for testability.
abstract class SpeechToTextWrapper {
  bool get isListening;
  bool get isAvailable;

  Future<bool> initialize({
    void Function(SpeechRecognitionError error)? onError,
    void Function(String status)? onStatus,
    Duration finalTimeout = const Duration(milliseconds: 2000),
  });

  Future<void> listen({
    required void Function(SpeechRecognitionResult result) onResult,
    void Function(double level)? onSoundLevelChange,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
    bool partialResults = true,
  });

  Future<void> stop();

  Future<void> cancel();
}

/// Default production implementation using the real SpeechToText instance.
class DefaultSpeechToTextWrapper implements SpeechToTextWrapper {
  DefaultSpeechToTextWrapper({SpeechToText? speechToText})
      : _speechToText = speechToText ?? SpeechToText();

  final SpeechToText _speechToText;

  @override
  bool get isListening => _speechToText.isListening;

  @override
  bool get isAvailable => _speechToText.isAvailable;

  @override
  Future<bool> initialize({
    void Function(SpeechRecognitionError error)? onError,
    void Function(String status)? onStatus,
    Duration finalTimeout = const Duration(milliseconds: 2000),
  }) {
    return _speechToText.initialize(
      onError: onError,
      onStatus: onStatus,
      finalTimeout: finalTimeout,
    );
  }

  @override
  Future<void> listen({
    required void Function(SpeechRecognitionResult result) onResult,
    void Function(double level)? onSoundLevelChange,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
    bool partialResults = true,
  }) {
    return _speechToText.listen(
      onResult: onResult,
      onSoundLevelChange: onSoundLevelChange,
      listenOptions: SpeechListenOptions(
        listenFor: listenFor,
        pauseFor: pauseFor,
        localeId: localeId,
        partialResults: partialResults,
      ),
    );
  }

  @override
  Future<void> stop() => _speechToText.stop();

  @override
  Future<void> cancel() => _speechToText.cancel();
}

/// Base contract for Voice Input Service streaming audio to text.
abstract class VoiceInputServiceBase {
  bool get isListening;
  bool get isAvailable;

  Stream<String> get transcriptionStream;
  Stream<double> get soundLevelStream;
  Stream<VoiceInputStatus> get statusStream;
  Stream<String> get errorStream;

  String get lastRecognizedWords;

  Future<Either<Failure, bool>> checkPermission();

  Future<Either<Failure, bool>> initialize();

  Future<Either<Failure, Unit>> startListening({
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
  });

  Future<Either<Failure, String>> stopListening();

  Future<void> cancelListening();

  void dispose();
}

/// Implementation of VoiceInputService using speech_to_text.
class VoiceInputService implements VoiceInputServiceBase {
  VoiceInputService({SpeechToTextWrapper? wrapper})
      : _wrapper = wrapper ?? DefaultSpeechToTextWrapper();

  final SpeechToTextWrapper _wrapper;

  final _transcriptionController = StreamController<String>.broadcast();
  final _soundLevelController = StreamController<double>.broadcast();
  final _statusController = StreamController<VoiceInputStatus>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  bool _isInitialized = false;
  String _lastRecognizedWords = '';
  VoiceInputStatus _currentStatus = VoiceInputStatus.idle;

  @override
  bool get isListening => _wrapper.isListening;

  @override
  bool get isAvailable => _wrapper.isAvailable;

  @override
  Stream<String> get transcriptionStream => _transcriptionController.stream;

  @override
  Stream<double> get soundLevelStream => _soundLevelController.stream;

  @override
  Stream<VoiceInputStatus> get statusStream => _statusController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  String get lastRecognizedWords => _lastRecognizedWords;

  VoiceInputStatus get currentStatus => _currentStatus;

  /// Normalizes raw decibel / level input to 0.0 - 1.0 range.
  static double normalizeSoundLevel(double raw) {
    if (raw.isNaN || raw.isInfinite) return 0.0;
    if (raw <= 0) {
      // Typically iOS / dB range -60.0 dB to 0.0 dB
      final val = (raw + 60.0) / 60.0;
      return val.clamp(0.0, 1.0);
    } else {
      // Typically Android / positive range 0.0 to 10.0 or 0.0 to 100.0
      final val = raw > 10.0 ? raw / 100.0 : raw / 10.0;
      return val.clamp(0.0, 1.0);
    }
  }

  @override
  Future<Either<Failure, bool>> initialize() async {
    try {
      final available = await _wrapper.initialize(
        onError: _handleError,
        onStatus: _handleStatus,
      );

      _isInitialized = available;

      if (!available) {
        return const Left(
          PermissionFailure(
            'Microphone or speech recognition permission denied or unavailable.',
          ),
        );
      }

      return const Right(true);
    } catch (e) {
      return Left(
        ServerFailure('Failed to initialize speech recognition: $e'),
      );
    }
  }

  @override
  Future<Either<Failure, bool>> checkPermission() async {
    if (!_isInitialized) {
      return initialize();
    }
    if (_wrapper.isAvailable) {
      return const Right(true);
    }
    return const Left(
      PermissionFailure('Microphone or speech recognition is unavailable.'),
    );
  }

  @override
  Future<Either<Failure, Unit>> startListening({
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
  }) async {
    if (!_isInitialized) {
      final initResult = await initialize();
      final hasInit = initResult.fold((failure) => false, (success) => success);
      if (!hasInit) {
        return initResult.fold(
          (failure) => Left(failure),
          (_) => const Left(
            PermissionFailure('Speech recognition initialization failed.'),
          ),
        );
      }
    }

    try {
      _lastRecognizedWords = '';
      _updateStatus(VoiceInputStatus.listening);

      await _wrapper.listen(
        onResult: _handleResult,
        onSoundLevelChange: _handleSoundLevel,
        listenFor: listenFor,
        pauseFor: pauseFor,
        localeId: localeId,
        partialResults: true,
      );

      return const Right(unit);
    } catch (e) {
      _updateStatus(VoiceInputStatus.error);
      _errorController.add(e.toString());
      return Left(ServerFailure('Failed to start speech listening: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> stopListening() async {
    try {
      await _wrapper.stop();
      _updateStatus(VoiceInputStatus.done);
      return Right(_lastRecognizedWords);
    } catch (e) {
      return Left(ServerFailure('Failed to stop speech listening: $e'));
    }
  }

  @override
  Future<void> cancelListening() async {
    try {
      await _wrapper.cancel();
    } finally {
      _lastRecognizedWords = '';
      _updateStatus(VoiceInputStatus.idle);
    }
  }

  void _handleResult(SpeechRecognitionResult result) {
    _lastRecognizedWords = result.recognizedWords;
    if (!_transcriptionController.isClosed) {
      _transcriptionController.add(result.recognizedWords);
    }
    if (result.finalResult) {
      _updateStatus(VoiceInputStatus.done);
    }
  }

  void _handleSoundLevel(double level) {
    if (!_soundLevelController.isClosed) {
      _soundLevelController.add(normalizeSoundLevel(level));
    }
  }

  void _handleError(SpeechRecognitionError error) {
    if (!_errorController.isClosed) {
      _errorController.add(error.errorMsg);
    }
    _updateStatus(VoiceInputStatus.error);
  }

  void _handleStatus(String status) {
    if (status == 'done' || status == 'notListening') {
      if (_currentStatus == VoiceInputStatus.listening) {
        _updateStatus(VoiceInputStatus.done);
      }
    }
  }

  void _updateStatus(VoiceInputStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  @override
  void dispose() {
    _transcriptionController.close();
    _soundLevelController.close();
    _statusController.close();
    _errorController.close();
  }
}
