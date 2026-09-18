import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

enum VoiceInputStatus { idle, listening, done, error }

/// Maximum listen window accepted by the `listen_voice_input` tool.
const int kMaxVoiceListenSeconds = 20;

/// Wall-clock ceiling for one `listen_voice_input` execution, declared so the
/// registry's two-stage budget is checkable.
///
/// A legitimate listen is capped at [kMaxVoiceListenSeconds] (20s) and the tool
/// settles when its status stream reports done/error, so the 2s of headroom exist
/// only so this backstop can never race the honest path. The speech plugin itself
/// is unbounded (`startListening` / `stopListening` await platform calls with no
/// timeout), so without this ceiling the registry's 25s execution bound is what
/// would fire and the tool's own window would be a fiction.
const Duration kVoiceInputToolWindow =
    Duration(seconds: kMaxVoiceListenSeconds + 2);

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
