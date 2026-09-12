import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

enum VoiceOutputStatus { idle, loading, playing, paused, stopped, error }

abstract class VoiceOutputServiceBase {
  bool get isPlaying;
  bool get isMuted;
  VoiceOutputStatus get currentStatus;
  int get queueLength;
  Stream<VoiceOutputStatus> get statusStream;
  Stream<String> get errorStream;

  void setMuted(bool muted);
  void toggleMute();
  Future<Either<Failure, Unit>> speakText(
    String text, {
    String? voice,
    String? model,
    double? speed,
  });
  Future<Either<Failure, Unit>> queueAudio(Uint8List audioBytes);
  Future<Either<Failure, Unit>> queueText(
    String text, {
    String? voice,
    String? model,
    double? speed,
  });
  Future<void> feedStreamingDelta(String delta);
  Future<void> flushStreaming();
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> interrupt();
  void dispose();
}
