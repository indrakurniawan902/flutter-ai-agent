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

  /// Reloads persisted engine/voice preference. Never throws.
  Future<void> loadPreferences() async {}
}

enum TtsEngineMode { system, piper }

/// Inner playback window for the offline Piper engine.
/// Deliberately SHORTER than the 45s it used to be: the registry's outer bound
/// for `speak_text` ([ToolRegistry.longWindowToolTimeout], 25s) must stay strictly
/// greater, and the device bridge gives the whole device call only 30s
/// (DEVICE_CALL_TIMEOUT), so a 45s playback window could never be reported honestly.
/// When playback does not settle in this window the engine returns false and the
/// service falls through to the system TTS / remote engine.
const Duration kPiperPlaybackTimeout = Duration(seconds: 18);

/// Thrown when a downloaded Piper voice model fails checksum/size validation.
class VoiceModelIntegrityException implements Exception {
  const VoiceModelIntegrityException(this.message);

  final String message;

  @override
  String toString() => 'VoiceModelIntegrityException: $message';
}

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
