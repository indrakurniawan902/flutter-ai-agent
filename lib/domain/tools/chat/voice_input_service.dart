import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

enum VoiceInputStatus { idle, listening, done, error }

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
