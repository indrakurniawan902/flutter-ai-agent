import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/constant.dart';
import 'package:flutter_ai_agent/common/exception.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';

abstract class AudioPlayerWrapper {
  Stream<PlayerState> get onPlayerStateChanged;
  Future<void> play(Source source);
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

class DefaultAudioPlayerWrapper implements AudioPlayerWrapper {
  DefaultAudioPlayerWrapper({AudioPlayer? player})
    : _player = _safeCreatePlayer(player);

  final AudioPlayer? _player;

  static AudioPlayer? _safeCreatePlayer(AudioPlayer? provided) {
    if (provided != null) return provided;
    try {
      return AudioPlayer();
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<PlayerState> get onPlayerStateChanged {
    try {
      return _player?.onPlayerStateChanged ?? const Stream.empty();
    } catch (_) {
      return const Stream.empty();
    }
  }

  @override
  Future<void> play(Source source) async {
    try {
      await _player?.play(source);
    } catch (_) {}
  }

  @override
  Future<void> pause() async {
    try {
      await _player?.pause();
    } catch (_) {}
  }

  @override
  Future<void> resume() async {
    try {
      await _player?.resume();
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      await _player?.setVolume(volume);
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    try {
      await _player?.dispose();
    } catch (_) {}
  }
}

@LazySingleton(as: PlatformTtsEngine)
class FlutterTtsPlatformEngine implements PlatformTtsEngine {
  FlutterTtsPlatformEngine() : _engine = _safeCreateEngine();

  final FlutterTts? _engine;
  bool _configured = false;

  static FlutterTts? _safeCreateEngine() {
    try {
      return FlutterTts();
    } catch (_) {
      return null;
    }
  }

  Future<void> _configure() async {
    if (_configured || _engine == null) return;
    try {
      await _engine.awaitSpeakCompletion(true);
      _configured = true;
    } catch (_) {}
  }

  @override
  bool get isAvailable {
    try {
      return _engine != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> speak(String text, {String? voice, double? speed}) async {
    try {
      final engine = _engine;
      if (engine == null) return false;
      await _configure();
      final result = await engine.speak(text);
      return result == 1 || result == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      await _engine?.setVolume(volume);
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _engine?.stop();
    } catch (_) {}
  }
}

abstract class TtsClient {
  Future<Uint8List> synthesize({
    required String text,
    String? voice,
    String? model,
    double? speed,
  });

  Future<bool> isRemoteConfigured();
}

class UnsupportedEndpointException implements Exception {
  final String message;
  const UnsupportedEndpointException([
    this.message = 'TTS endpoint not supported by the active server or router',
  ]);
}

@LazySingleton(as: TtsClient)
class DioTtsClient implements TtsClient {
  static const String unsupportedEndpointMessage =
      'TTS endpoint not supported by the active server/router';

  DioTtsClient({
    required Dio dio,
    String? baseUrl,
    String? apiKey,
    SecureStorageService? secureStorageService,
  }) : _dio = dio,
       _baseUrl = baseUrl ?? '',
       _apiKey = apiKey,
       _secureStorageService = secureStorageService;

  @factoryMethod
  factory DioTtsClient.create(
    Dio dio, [
    SecureStorageService? secureStorageService,
  ]) => DioTtsClient(dio: dio, secureStorageService: secureStorageService);

  final Dio _dio;
  final String _baseUrl;
  final String? _apiKey;
  final SecureStorageService? _secureStorageService;

  @override
  Future<bool> isRemoteConfigured() async {
    if (_baseUrl.trim().isNotEmpty) return true;
    final stored = await _secureStorageService?.getBaseUrl();
    return stored != null && stored.trim().isNotEmpty;
  }

  @override
  Future<Uint8List> synthesize({
    required String text,
    String? voice,
    String? model,
    double? speed,
  }) async {
    var effectiveBaseUrl = _baseUrl.trim();
    if (effectiveBaseUrl.isEmpty && _secureStorageService != null) {
      final stored = await _secureStorageService.getBaseUrl();
      if (stored != null && stored.trim().isNotEmpty) {
        effectiveBaseUrl = stored.trim();
      }
    }
    if (effectiveBaseUrl.isEmpty) {
      effectiveBaseUrl = AppConstants.defaultBaseUrl;
    }

    while (effectiveBaseUrl.endsWith('/')) {
      effectiveBaseUrl = effectiveBaseUrl.substring(
        0,
        effectiveBaseUrl.length - 1,
      );
    }

    final String endpoint;
    if (effectiveBaseUrl.endsWith('/audio/speech')) {
      endpoint = effectiveBaseUrl;
    } else if (effectiveBaseUrl.endsWith('/v1')) {
      endpoint = '$effectiveBaseUrl/audio/speech';
    } else {
      endpoint = '$effectiveBaseUrl/v1/audio/speech';
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    var apiKey = _apiKey;
    if ((apiKey == null || apiKey.isEmpty) && _secureStorageService != null) {
      apiKey = await _secureStorageService.getApiKey();
    }
    if (apiKey != null && apiKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $apiKey';
    }

    final payload = <String, dynamic>{
      'model': model ?? 'tts-1',
      'input': text,
      'voice': voice ?? 'alloy',
      'speed': ?speed,
      'response_format': 'mp3',
    };
    final Response<List<int>> response;
    try {
      response = await _dio.post<List<int>>(
        endpoint,
        data: payload,
        options: Options(responseType: ResponseType.bytes, headers: headers),
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404) {
        throw const UnsupportedEndpointException(
          DioTtsClient.unsupportedEndpointMessage,
        );
      }
      rethrow;
    }
    final bytes = response.data;
    if (response.statusCode == 404) {
      throw const UnsupportedEndpointException(
        DioTtsClient.unsupportedEndpointMessage,
      );
    }
    if (response.statusCode != 200 || bytes == null) {
      throw ServerException(
        response.statusMessage ?? 'TTS request failed',
        response.statusCode,
      );
    }
    return Uint8List.fromList(bytes);
  }
}

@LazySingleton(as: VoiceOutputServiceBase)
class VoiceOutputService implements VoiceOutputServiceBase {
  VoiceOutputService({
    required TtsClient ttsClient,
    AudioPlayerWrapper? audioPlayer,
    PlatformTtsEngine? platformTts,
    PiperTtsEngineBase? piperTts,
    PiperVoiceStoreBase? piperVoiceStore,
    SecureStorageService? secureStorage,
  }) : _tts = ttsClient,
       _player = audioPlayer ?? DefaultAudioPlayerWrapper(),
       _platformTts = platformTts ?? FlutterTtsPlatformEngine(),
       _piperTts = piperTts,
       _piperVoiceStore = piperVoiceStore,
       _secureStorage = secureStorage {
    StreamSubscription<PlayerState> sub;
    try {
      sub = _player.onPlayerStateChanged.listen(_onPlayerState);
    } catch (_) {
      sub = Stream<PlayerState>.empty().listen((_) {});
    }
    _playerStateSub = sub;
  }

  @factoryMethod
  factory VoiceOutputService.create(
    TtsClient ttsClient,
    PlatformTtsEngine platformTts, [
    PiperTtsEngineBase? piperTts,
    PiperVoiceStoreBase? piperVoiceStore,
    SecureStorageService? secureStorage,
  ]) => VoiceOutputService(
    ttsClient: ttsClient,
    platformTts: platformTts,
    piperTts: piperTts,
    piperVoiceStore: piperVoiceStore,
    secureStorage: secureStorage,
  );

  static const _streamFlushThreshold = 120;

  final TtsClient _tts;
  final AudioPlayerWrapper _player;
  final PlatformTtsEngine _platformTts;
  final PiperTtsEngineBase? _piperTts;
  final PiperVoiceStoreBase? _piperVoiceStore;
  final SecureStorageService? _secureStorage;
  late final StreamSubscription<PlayerState> _playerStateSub;

  /// Default catalog voice used when piper mode is selected.
  static const String defaultPiperVoiceId = 'id_ID-news_tts-medium';

  TtsEngineMode _engineMode = TtsEngineMode.system;
  String _piperVoiceId = defaultPiperVoiceId;
  bool _preferenceLoaded = false;

  TtsEngine? _lastEngineUsed;

  int _platformEpoch = 0;

  final _statusController = StreamController<VoiceOutputStatus>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  final _queue = <Uint8List>[];
  final _streamBuffer = StringBuffer();

  bool _muted = false;
  bool _playing = false;
  VoiceOutputStatus _status = VoiceOutputStatus.idle;

  @override
  bool get isPlaying => _playing;

  @override
  bool get isMuted => _muted;

  @override
  VoiceOutputStatus get currentStatus => _status;

  @override
  int get queueLength => _queue.length;

  @override
  TtsEngine? get lastEngineUsed => _lastEngineUsed;

  @override
  TtsEngineMode get preferredEngineMode => _engineMode;

  @override
  void setPreferredEngineMode(TtsEngineMode mode) {
    _engineMode = mode;
    try {
      unawaited(
        _secureStorage?.saveTtsEngineMode(
          mode == TtsEngineMode.piper ? 'piper' : 'system',
        ),
      );
    } catch (_) {}
  }

  /// Catalog voice id used when [preferredEngineMode] is piper.
  @override
  String get piperVoiceId => _piperVoiceId;

  @override
  void setPiperVoiceId(String voiceId) {
    _piperVoiceId = voiceId;
    try {
      unawaited(_secureStorage?.savePiperVoiceId(voiceId));
    } catch (_) {}
    unawaited(_loadPiperVoice());
  }

  /// Loads persisted engine mode + voice id. Never throws.
  @override
  Future<void> loadPreferences() async {
    try {
      String? modeStr;
      String? voiceId;
      try {
        modeStr = await _secureStorage?.getTtsEngineMode();
      } catch (_) {
        modeStr = null;
      }
      try {
        voiceId = await _secureStorage?.getPiperVoiceId();
      } catch (_) {
        voiceId = null;
      }
      _engineMode = modeStr == 'piper'
          ? TtsEngineMode.piper
          : TtsEngineMode.system;
      if (voiceId != null && voiceId.trim().isNotEmpty) {
        _piperVoiceId = voiceId.trim();
      } else {
        _piperVoiceId = defaultPiperVoiceId;
      }
      // Touch the voice store so the injected instance stays referenced.
      try {
        _piperVoiceStore?.modelDirFor(_piperVoiceId);
      } catch (_) {}
      try {
        await _piperTts?.prepare(_piperVoiceId);
      } catch (_) {}
    } catch (_) {
      // Never throw out of preference loading.
    } finally {
      _preferenceLoaded = true;
    }
  }

  Future<void> _ensurePreferencesLoaded() async {
    if (_preferenceLoaded) return;
    await loadPreferences();
  }

  Future<void> _loadPiperVoice() async {
    try {
      await _piperTts?.prepare(_piperVoiceId);
    } catch (_) {}
  }

  /// Tries offline Piper synthesis. Returns true when speech was handled.
  /// Any failure returns false so callers fall through to the system path.
  Future<bool> _trySpeakWithPiper(
    String text, {
    String? voice,
    double? speed,
  }) async {
    try {
      final piper = _piperTts;
      if (piper == null) return false;
      bool available = false;
      try {
        available = piper.isAvailable;
      } catch (_) {
        return false;
      }
      if (!available) return false;
      bool prepared = false;
      try {
        prepared = await piper.prepare(_piperVoiceId);
      } catch (_) {
        return false;
      }
      if (!prepared) return false;
      bool spoke = false;
      try {
        _setStatus(VoiceOutputStatus.loading);
        _playing = true;
        _setStatus(VoiceOutputStatus.playing);
        spoke = await piper.speak(text, voice: voice, speed: speed);
      } catch (_) {
        _playing = false;
        return false;
      }
      if (!spoke) {
        _playing = false;
        return false;
      }
      _lastEngineUsed = TtsEngine.piperTts;
      _playing = false;
      _setStatus(VoiceOutputStatus.idle);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Piper-mode chain: piper -> system TTS -> remote.
  /// Shared by [speakText] and [queueText] so the two call sites stay
  /// identical. [isQueueText] selects the remote error message.
  /// Never throws: any failure degrades to the next step.
  Future<Either<Failure, Unit>> _speakWithPiperChain(
    String text, {
    String? voice,
    String? model,
    double? speed,
    required bool isQueueText,
  }) async {
    try {
      if (await _trySpeakWithPiper(text, voice: voice, speed: speed)) {
        return const Right(unit);
      }
    } catch (_) {
      // Fall through to system TTS.
    }
    Either<Failure, Unit> platformResult;
    try {
      platformResult = await _speakWithPlatform(
        text,
        voice: voice,
        speed: speed,
      );
    } catch (e) {
      platformResult = Left(ServerFailure('Platform TTS failed: $e'));
    }
    if (platformResult.isRight()) return platformResult;
    bool remoteConfigured = false;
    try {
      remoteConfigured = await _tts.isRemoteConfigured();
    } catch (_) {
      return platformResult;
    }
    if (remoteConfigured) {
      try {
        _setStatus(VoiceOutputStatus.loading);
        final bytes = await _tts.synthesize(
          text: text,
          voice: voice,
          model: model,
          speed: speed,
        );
        _lastEngineUsed = TtsEngine.remoteTts;
        return await queueAudio(bytes);
      } on UnsupportedEndpointException {
        return platformResult;
      } catch (e) {
        if (isQueueText) {
          _fail('Text queue failed: $e');
          return Left(ServerFailure('Text queue failed: $e'));
        }
        _fail('Speech synthesis failed: $e');
        return Left(ServerFailure('Speech synthesis failed: $e'));
      }
    }
    return platformResult;
  }

  @override
  Stream<VoiceOutputStatus> get statusStream => _statusController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  void setMuted(bool muted) {
    _muted = muted;
    unawaited(_player.setVolume(muted ? 0.0 : 1.0));
    unawaited(_platformTts.setVolume(muted ? 0.0 : 1.0));
    unawaited(_piperTts?.setVolume(muted ? 0.0 : 1.0));
  }

  @override
  void toggleMute() => setMuted(!_muted);

  @override
  Future<Either<Failure, Unit>> speakText(
    String text, {
    String? voice,
    String? model,
    double? speed,
  }) async {
    if (text.trim().isEmpty) {
      return const Left(ServerFailure('Cannot speak empty text'));
    }
    await _ensurePreferencesLoaded();
    if (_engineMode == TtsEngineMode.piper) {
      return _speakWithPiperChain(
        text,
        voice: voice,
        model: model,
        speed: speed,
        isQueueText: false,
      );
    }
    if (!await _tts.isRemoteConfigured()) {
      return _speakWithPlatform(text, voice: voice, speed: speed);
    }
    try {
      _setStatus(VoiceOutputStatus.loading);
      final bytes = await _tts.synthesize(
        text: text,
        voice: voice,
        model: model,
        speed: speed,
      );
      _lastEngineUsed = TtsEngine.remoteTts;
      return await queueAudio(bytes);
    } on UnsupportedEndpointException {
      return _speakWithPlatform(text, voice: voice, speed: speed);
    } catch (e) {
      _fail('Speech synthesis failed: $e');
      return Left(ServerFailure('Speech synthesis failed: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> queueAudio(Uint8List audioBytes) async {
    try {
      _queue.add(audioBytes);
      if (!_playing) await _playNext();
      return const Right(unit);
    } catch (e) {
      _fail('Audio queue failed: $e');
      return Left(ServerFailure('Audio queue failed: $e'));
    }
  }

  @override
  Future<Either<Failure, Unit>> queueText(
    String text, {
    String? voice,
    String? model,
    double? speed,
  }) async {
    if (text.trim().isEmpty) {
      return const Left(ServerFailure('Cannot queue empty text'));
    }
    await _ensurePreferencesLoaded();
    if (_engineMode == TtsEngineMode.piper) {
      return _speakWithPiperChain(
        text,
        voice: voice,
        model: model,
        speed: speed,
        isQueueText: true,
      );
    }
    if (!await _tts.isRemoteConfigured()) {
      // Platform speech is immediate (no byte queue); streaming flush awaits completion.
      return _speakWithPlatform(text, voice: voice, speed: speed);
    }
    try {
      final bytes = await _tts.synthesize(
        text: text,
        voice: voice,
        model: model,
        speed: speed,
      );
      _lastEngineUsed = TtsEngine.remoteTts;
      return await queueAudio(bytes);
    } on UnsupportedEndpointException {
      return _speakWithPlatform(text, voice: voice, speed: speed);
    } catch (e) {
      _fail('Text queue failed: $e');
      return Left(ServerFailure('Text queue failed: $e'));
    }
  }

  Future<Either<Failure, Unit>> _speakWithPlatform(
    String text, {
    String? voice,
    double? speed,
  }) async {
    try {
      _setStatus(VoiceOutputStatus.loading);
      _playing = true;
      _setStatus(VoiceOutputStatus.playing);
      final epoch = _platformEpoch;
      final spoke = await _platformTts.speak(text, voice: voice, speed: speed);
      if (_platformEpoch != epoch) {
        // Interrupted: stop() already emitted the stopped status.
        return const Right(unit);
      }
      if (!spoke) {
        _fail('Platform TTS failed to speak the provided text');
        return const Left(
          ServerFailure('Platform TTS failed to speak the provided text'),
        );
      }
      _lastEngineUsed = TtsEngine.androidTts;
      _playing = false;
      _setStatus(VoiceOutputStatus.idle);
      return const Right(unit);
    } catch (e) {
      _fail('Platform TTS failed: $e');
      return Left(ServerFailure('Platform TTS failed: $e'));
    }
  }

  @override
  Future<void> feedStreamingDelta(String delta) async {
    _streamBuffer.write(delta);
    if (_shouldFlushStreamBuffer) await flushStreaming();
  }

  bool get _shouldFlushStreamBuffer {
    final text = _streamBuffer.toString();
    if (text.length < _streamFlushThreshold) return false;
    return RegExp(r'[.!?;:]\s?$').hasMatch(text);
  }

  @override
  Future<void> flushStreaming() async {
    final text = _streamBuffer.toString().trim();
    _streamBuffer.clear();
    if (text.isEmpty) return;
    await queueText(text);
  }

  @override
  Future<void> pause() async {
    await _player.pause();
    _setStatus(VoiceOutputStatus.paused);
  }

  @override
  Future<void> resume() async {
    await _player.resume();
    _setStatus(VoiceOutputStatus.playing);
  }

  @override
  Future<void> stop() async {
    _platformEpoch++;
    await _platformTts.stop();
    try {
      await _piperTts?.stop();
    } catch (_) {}
    await _player.stop();
    _playing = false;
    _setStatus(VoiceOutputStatus.stopped);
  }

  @override
  Future<void> interrupt() async {
    _queue.clear();
    _streamBuffer.clear();
    _platformEpoch++;
    await stop();
  }

  @override
  void dispose() {
    unawaited(_playerStateSub.cancel());
    unawaited(_player.dispose());
    _statusController.close();
    _errorController.close();
  }

  Future<void> _playNext() async {
    if (_queue.isEmpty) {
      _playing = false;
      _setStatus(VoiceOutputStatus.idle);
      return;
    }
    final next = _queue.removeAt(0);
    try {
      _playing = true;
      _setStatus(VoiceOutputStatus.playing);
      if (_muted) await _player.setVolume(0.0);
      await _player.play(BytesSource(next));
    } catch (e) {
      _playing = false;
      _fail('Audio playback failed: $e');
      await _playNext();
    }
  }

  void _onPlayerState(PlayerState state) {
    switch (state) {
      case PlayerState.completed:
        unawaited(_playNext());
      case PlayerState.stopped:
        _playing = false;
        _setStatus(VoiceOutputStatus.stopped);
      case PlayerState.paused:
        _setStatus(VoiceOutputStatus.paused);
      case PlayerState.playing:
        _playing = true;
        _setStatus(VoiceOutputStatus.playing);
      case PlayerState.disposed:
        _playing = false;
    }
  }

  void _setStatus(VoiceOutputStatus status) {
    _status = status;
    if (!_statusController.isClosed) _statusController.add(status);
  }

  void _fail(String message) {
    _playing = false;
    _setStatus(VoiceOutputStatus.error);
    if (!_errorController.isClosed) _errorController.add(message);
  }
}
