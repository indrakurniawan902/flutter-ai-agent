import 'dart:typed_data';

import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/piper_voice.dart';

enum VoiceOutputStatus { idle, loading, playing, paused, stopped, error }

enum TtsEngine { remoteTts, androidTts, piperTts }

abstract class PlatformTtsEngine {
  bool get isAvailable;
  Future<bool> speak(String text, {String? voice, double? speed});
  Future<void> setVolume(double volume);
  Future<void> stop();
}

abstract class VoiceOutputServiceBase {
  bool get isPlaying;
  bool get isMuted;
  VoiceOutputStatus get currentStatus;
  int get queueLength;
  TtsEngine? get lastEngineUsed;
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

  /// Engine preference persisted from Settings (default system).
  TtsEngineMode get preferredEngineMode => TtsEngineMode.system;
  void setPreferredEngineMode(TtsEngineMode mode) {}

  /// Catalog voice id used when [preferredEngineMode] is piper.
  String get piperVoiceId => 'id_ID-news_tts-medium';
  void setPiperVoiceId(String voiceId) {}
}

enum TtsEngineMode { system, piper }

/// Contract for the on-demand Piper voice model store
/// (download/verify/locate).
abstract class PiperVoiceStoreBase {
  /// Absolute dir for the extracted model of [voiceId]
  /// (does not imply it exists).
  String modelDirFor(String voiceId);

  /// True when `<model>.onnx` + `tokens.txt` + `espeak-ng-data/`
  /// all exist.
  Future<bool> isVoiceReady(String voiceId);

  /// Download tarball -> MD5 verify -> extract. Returns Ready error
  /// on mismatch.
  /// [onProgress] gets 0..1 (fraction of expected bytes received).
  Future<void> downloadVoice(
    PiperVoiceDescriptor voice, {
    void Function(double progress)? onProgress,
  });
  Future<void> deleteVoice(String voiceId);
}

/// Platform engine that synthesizes offline via Piper neural TTS.
abstract class PiperTtsEngineBase implements PlatformTtsEngine {
  /// Voice id currently loaded (null when no model ready yet).
  String? get activeVoiceId;

  /// Loads (or reloads) native engine with [voiceId]'s model. Returns
  /// false when model files are missing. Never throws.
  Future<bool> prepare(String voiceId);
}
