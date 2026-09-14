import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

import 'package:flutter_ai_agent/data/datasources/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/piper_voice.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';

/// Plain audio buffer returned by [SherpaTtsWrapper.synthesize].
class GeneratedAudioData {
  const GeneratedAudioData({required this.samples, required this.sampleRate});

  final Float32List samples;
  final int sampleRate;
}

/// Thin seam over `package:sherpa_onnx` so tests never load native libs.
abstract class SherpaTtsWrapper {
  static bool bindingsInitialized = false;

  /// Loads native bindings once; safe to call repeatedly.
  void ensureBindings();

  /// Synthesizes [text] with the VITS model at [modelPath].
  GeneratedAudioData synthesize({
    required String modelPath,
    required String tokensPath,
    required String dataDirPath,
    required String text,
    int sid = 0,
    double speed = 1.0,
  });
}

/// Real FFI implementation of [SherpaTtsWrapper].
class DefaultSherpaTtsWrapper implements SherpaTtsWrapper {
  @override
  void ensureBindings() {
    if (SherpaTtsWrapper.bindingsInitialized) return;
    try {
      sherpa_onnx.initBindings();
      SherpaTtsWrapper.bindingsInitialized = true;
    } catch (_) {
      rethrow;
    }
  }

  @override
  GeneratedAudioData synthesize({
    required String modelPath,
    required String tokensPath,
    required String dataDirPath,
    required String text,
    int sid = 0,
    double speed = 1.0,
  }) {
    ensureBindings();
    final config = sherpa_onnx.OfflineTtsConfig(
      model: sherpa_onnx.OfflineTtsModelConfig(
        vits: sherpa_onnx.OfflineTtsVitsModelConfig(
          model: modelPath,
          tokens: tokensPath,
          dataDir: dataDirPath,
        ),
      ),
    );
    final tts = sherpa_onnx.OfflineTts(config);
    try {
      final audio = tts.generate(text: text, sid: sid, speed: speed);
      return GeneratedAudioData(
        samples: audio.samples,
        sampleRate: audio.sampleRate,
      );
    } finally {
      try {
        tts.free();
      } catch (_) {}
    }
  }
}

/// Resolves the `<id>.onnx` file name, falling back to `<id>.onnx`
/// for ids outside the catalog (e.g. in tests).
String _voiceModelFileName(String voiceId) =>
    piperVoiceById(voiceId)?.modelFileName ?? '$voiceId.onnx';

String _joinPath(String first, String second) {
  final sep = Platform.pathSeparator;
  var head = first;
  while (head.endsWith(sep) && head.length > 1) {
    head = head.substring(0, head.length - 1);
  }
  return '$head$sep$second';
}

/// On-demand store for Piper voice models: download, MD5-verify,
/// extract and locate model files under `<documents>/tts_models/`.
@LazySingleton(as: PiperVoiceStoreBase)
class PiperVoiceStore implements PiperVoiceStoreBase {
  PiperVoiceStore({
    Dio? dio,
    Future<Directory> Function()? documentsDirProvider,
    String Function()? rootDirPath,
    bool Function(String path)? fileExists,
    bool Function(String path)? dirExists,
    Future<Uint8List> Function(String url, void Function(double progress))?
    fetchBytes,
  }) : _dio = dio,
       _documentsDirProvider =
           documentsDirProvider ?? getApplicationDocumentsDirectory,
       _rootDirPathOverride = rootDirPath,
       _fileExists = fileExists ?? _defaultFileExists,
       _dirExists = dirExists ?? _defaultDirExists,
       _fetchBytes = fetchBytes;

  /// Injectable-friendly creator; real defaults resolve lazily.
  @factoryMethod
  factory PiperVoiceStore.create() => PiperVoiceStore();

  final Dio? _dio;
  final Future<Directory> Function() _documentsDirProvider;
  final String Function()? _rootDirPathOverride;
  final bool Function(String path) _fileExists;
  final bool Function(String path) _dirExists;
  final Future<Uint8List> Function(String url, void Function(double progress))?
  _fetchBytes;

  String? _cachedModelsRoot;

  static bool _defaultFileExists(String path) {
    try {
      return File(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  static bool _defaultDirExists(String path) {
    try {
      return Directory(path).existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<String> _modelsRoot() async {
    final override = _rootDirPathOverride?.call();
    if (override != null) return override;
    final cached = _cachedModelsRoot;
    if (cached != null) return cached;
    final docs = await _documentsDirProvider();
    final root = _joinPath(docs.path, 'tts_models');
    _cachedModelsRoot = root;
    return root;
  }

  @override
  String modelDirFor(String voiceId) {
    // Sync contract: prefers the injected root, then the cached
    // documents path once any async call has resolved it.
    final override = _rootDirPathOverride?.call();
    return _joinPath(override ?? _cachedModelsRoot ?? 'tts_models', voiceId);
  }

  @override
  Future<bool> isVoiceReady(String voiceId) async {
    try {
      final dir = _joinPath(await _modelsRoot(), voiceId);
      final sep = Platform.pathSeparator;
      final modelOk = _fileExists('$dir$sep${_voiceModelFileName(voiceId)}');
      final tokensOk = _fileExists('$dir${sep}tokens.txt');
      final dataOk = _dirExists('$dir${sep}espeak-ng-data');
      return modelOk && tokensOk && dataOk;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> downloadVoice(
    PiperVoiceDescriptor voice, {
    void Function(double progress)? onProgress,
  }) async {
    final modelsRoot = await _modelsRoot();
    final tmpDirPath = _joinPath(modelsRoot, 'tmp');
    await Directory(tmpDirPath).create(recursive: true);
    final tmpPath = _joinPath(tmpDirPath, voice.tarballName);
    final tmpFile = File(tmpPath);

    final fetch = _fetchBytes;
    if (fetch != null) {
      final bytes = await fetch(voice.downloadUrl, (p) => onProgress?.call(p));
      await tmpFile.writeAsBytes(bytes, flush: true);
    } else {
      final dio =
          _dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: Duration.zero,
            ),
          );
      await dio.download(
        voice.downloadUrl,
        tmpPath,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
      );
    }

    final digest = await md5.bind(tmpFile.openRead()).first;
    if (digest.toString() != voice.tarballMd5.toLowerCase()) {
      try {
        await tmpFile.delete();
      } catch (_) {}
      throw VoiceModelIntegrityException(
        'MD5 mismatch for ${voice.tarballName}',
      );
    }

    // Peak memory ~230MB one-time: the bzip2 payload and the decoded
    // tar coexist briefly. Acceptable for a once-per-install operation.
    try {
      final tarBytes = BZip2Decoder().decodeBytes(await tmpFile.readAsBytes());
      final archive = TarDecoder().decodeBytes(tarBytes);
      final prefix = 'vits-piper-${voice.id}/';
      final destDir = _joinPath(modelsRoot, voice.id);
      final sep = Platform.pathSeparator;
      for (final entry in archive.files.toList()) {
        if (!entry.isFile || entry.isSymbolicLink) continue;
        final name = entry.name;
        if (!name.startsWith(prefix)) continue;
        final relative = name.substring(prefix.length);
        if (relative.isEmpty || relative.contains('..')) continue;
        final outFile = File(_joinPath(destDir, relative.replaceAll('/', sep)));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(entry.content, flush: true);
        archive.removeFile(entry);
      }
    } finally {
      try {
        await tmpFile.delete();
      } catch (_) {}
    }

    if (!await isVoiceReady(voice.id)) {
      try {
        final dest = Directory(_joinPath(modelsRoot, voice.id));
        if (await dest.exists()) await dest.delete(recursive: true);
      } catch (_) {}
      throw VoiceModelIntegrityException(
        'Archive for ${voice.id} did not contain the expected model files',
      );
    }
    final destDir = _joinPath(modelsRoot, voice.id);
    final sidecar = File(_joinPath(destDir, '${voice.id}.onnx.json'));
    if (await sidecar.exists()) {
      try {
        await sidecar.delete();
      } catch (_) {}
    }
  }

  @override
  Future<void> deleteVoice(String voiceId) async {
    final modelsRoot = await _modelsRoot();
    final dir = Directory(_joinPath(modelsRoot, voiceId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    final voice = piperVoiceById(voiceId);
    if (voice != null) {
      final tmp = File(
        _joinPath(_joinPath(modelsRoot, 'tmp'), voice.tarballName),
      );
      if (await tmp.exists()) {
        await tmp.delete();
      }
    }
  }
}

/// Offline Piper TTS platform engine backed by sherpa-onnx VITS.
@LazySingleton(as: PiperTtsEngineBase)
class PiperTtsEngine implements PiperTtsEngineBase {
  PiperTtsEngine({
    required PiperVoiceStoreBase store,
    SherpaTtsWrapper? sherpa,
    AudioPlayerWrapper? player,
    bool Function()? nativeSupported,
    Duration playbackTimeout = const Duration(seconds: 45),
  }) : _store = store,
       _sherpa = sherpa ?? DefaultSherpaTtsWrapper(),
       _player = player,
       _nativeSupported = nativeSupported,
       _playbackTimeout = playbackTimeout;

  /// Injectable-friendly creator.
  @factoryMethod
  factory PiperTtsEngine.create(PiperVoiceStoreBase store) =>
      PiperTtsEngine(store: store);

  final PiperVoiceStoreBase _store;
  final SherpaTtsWrapper _sherpa;
  AudioPlayerWrapper? _player;
  final bool Function()? _nativeSupported;
  final Duration _playbackTimeout;

  /// Lazily builds the audio player so DI resolution never touches a
  /// platform plugin in test environments.
  AudioPlayerWrapper get _audioPlayer =>
      _player ??= DefaultAudioPlayerWrapper();

  String? _preparedVoiceId;
  String? _modelPath;
  String? _tokensPath;
  String? _dataDirPath;

  void _clearPrepared() {
    _preparedVoiceId = null;
    _modelPath = null;
    _tokensPath = null;
    _dataDirPath = null;
  }

  @override
  String? get activeVoiceId => _preparedVoiceId;

  @override
  Future<bool> prepare(String voiceId) async {
    try {
      if (!await _store.isVoiceReady(voiceId)) {
        _clearPrepared();
        return false;
      }
      final dir = _store.modelDirFor(voiceId);
      final sep = Platform.pathSeparator;
      _modelPath = '$dir$sep${_voiceModelFileName(voiceId)}';
      _tokensPath = '$dir${sep}tokens.txt';
      _dataDirPath = '$dir${sep}espeak-ng-data';
      _preparedVoiceId = voiceId;
      return true;
    } catch (_) {
      _clearPrepared();
      return false;
    }
  }

  @override
  bool get isAvailable => _preparedVoiceId != null && Platform.isAndroid;

  @override
  Future<bool> speak(String text, {String? voice, double? speed}) async {
    // `voice` is intentionally ignored: the catalog voice is fixed
    // by prepare().
    try {
      final supported = _nativeSupported?.call() ?? Platform.isAndroid;
      if (!supported) return false;
      final modelPath = _modelPath;
      final tokensPath = _tokensPath;
      final dataDirPath = _dataDirPath;
      if (_preparedVoiceId == null ||
          modelPath == null ||
          tokensPath == null ||
          dataDirPath == null) {
        return false;
      }
      final audio = _sherpa.synthesize(
        modelPath: modelPath,
        tokensPath: tokensPath,
        dataDirPath: dataDirPath,
        text: text,
        speed: speed ?? 1.0,
      );
      if (audio.samples.isEmpty) return false;
      final wav = _encodeWav16Mono(audio.samples, audio.sampleRate);
      await _audioPlayer.play(BytesSource(wav));
      final PlayerState finalState;
      try {
        finalState = await _audioPlayer.onPlayerStateChanged
            .firstWhere(
              (state) =>
                  state == PlayerState.completed ||
                  state == PlayerState.stopped,
            )
            .timeout(_playbackTimeout);
      } on TimeoutException {
        // Playback never settled: report failure so the caller can fall
        // through to the system TTS / remote engine.
        return false;
      }
      return finalState == PlayerState.completed;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      final player = _player;
      if (player == null) return;
      await player.setVolume(volume);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      final player = _player;
      if (player == null) return;
      await player.stop();
    } catch (_) {}
  }
}

/// Encodes mono float samples as 16-bit PCM WAV bytes.
Uint8List _encodeWav16Mono(Float32List samples, int sampleRate) {
  final dataSize = samples.length * 2;
  final out = ByteData(44 + dataSize);

  void writeAscii(int offset, String text) {
    for (var i = 0; i < text.length; i++) {
      out.setUint8(offset + i, text.codeUnitAt(i));
    }
  }

  writeAscii(0, 'RIFF');
  out.setUint32(4, 36 + dataSize, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  out.setUint32(16, 16, Endian.little);
  out.setUint16(20, 1, Endian.little);
  out.setUint16(22, 1, Endian.little);
  out.setUint32(24, sampleRate, Endian.little);
  out.setUint32(28, sampleRate * 2, Endian.little);
  out.setUint16(32, 2, Endian.little);
  out.setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  out.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    out.setInt16(44 + i * 2, v, Endian.little);
  }
  return out.buffer.asUint8List();
}
