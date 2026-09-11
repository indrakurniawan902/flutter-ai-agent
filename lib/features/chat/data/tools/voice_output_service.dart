import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';

/// Status of voice output playback.
enum VoiceOutputStatus {
  idle,
  loading,
  playing,
  paused,
  stopped,
  error,
}

/// Abstract platform wrapper around AudioPlayer for testability.
abstract class AudioPlayerWrapper {
  PlayerState get state;
  Stream<void> get onPlayerComplete;
  Stream<PlayerState> get onPlayerStateChanged;

  Future<void> playBytes(Uint8List bytes, {double? volume});
  Future<void> playUrl(String url, {double? volume});
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

/// Default AudioPlayer implementation wrapping audioplayers package.
class DefaultAudioPlayerWrapper implements AudioPlayerWrapper {
  DefaultAudioPlayerWrapper({AudioPlayer? player})
      : _player = player ?? AudioPlayer();

  final AudioPlayer _player;

  @override
  PlayerState get state {
    try {
      return _player.state;
    } catch (_) {
      return PlayerState.stopped;
    }
  }

  @override
  Stream<void> get onPlayerComplete {
    try {
      return _player.onPlayerComplete;
    } catch (_) {
      return const Stream.empty();
    }
  }

  @override
  Stream<PlayerState> get onPlayerStateChanged {
    try {
      return _player.onPlayerStateChanged;
    } catch (_) {
      return const Stream.empty();
    }
  }

  @override
  Future<void> playBytes(Uint8List bytes, {double? volume}) async {
    await _player.play(BytesSource(bytes), volume: volume);
  }

  @override
  Future<void> playUrl(String url, {double? volume}) async {
    await _player.play(UrlSource(url), volume: volume);
  }

  @override
  Future<void> pause() async {
    try {
      await _player.pause();
    } catch (_) {}
  }

  @override
  Future<void> resume() async {
    try {
      await _player.resume();
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    try {
      await _player.stop();
    } catch (_) {}
  }

  @override
  Future<void> setVolume(double volume) async {
    try {
      await _player.setVolume(volume);
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    try {
      await _player.dispose();
    } catch (_) {}
  }
}

/// Text-to-Speech synthesis client contract.
abstract class TtsClient {
  Future<Either<Failure, Uint8List>> synthesizeSpeech({
    required String text,
    String? voice,
    String? model,
    double? speed,
  });
}

/// Dio-backed implementation for OpenAI-compatible `/audio/speech` endpoint.
class DioTtsClient implements TtsClient {
  DioTtsClient({
    required Dio dio,
    Future<String?> Function()? getBaseUrl,
    Future<String?> Function()? getApiKey,
  })  : _dio = dio,
        _getBaseUrl = getBaseUrl,
        _getApiKey = getApiKey;

  final Dio _dio;
  final Future<String?> Function()? _getBaseUrl;
  final Future<String?> Function()? _getApiKey;

  @override
  Future<Either<Failure, Uint8List>> synthesizeSpeech({
    required String text,
    String? voice,
    String? model,
    double? speed,
  }) async {
    try {
      final rawBaseUrl =
          (await _getBaseUrl?.call()) ?? 'https://api.openai.com/v1';
      final apiKey = await _getApiKey?.call();

      final cleanBaseUrl = rawBaseUrl.endsWith('/')
          ? rawBaseUrl.substring(0, rawBaseUrl.length - 1)
          : rawBaseUrl;
      final endpoint = '$cleanBaseUrl/audio/speech';

      final headers = <String, dynamic>{
        'Content-Type': 'application/json',
      };
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

      final response = await _dio.post<List<int>>(
        endpoint,
        data: payload,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
        ),
      );

      if (response.data != null) {
        return Right(Uint8List.fromList(response.data!));
      } else {
        return const Left(ServerFailure('TTS response returned empty body'));
      }
    } on DioException catch (dioError) {
      if (dioError.type == DioExceptionType.connectionTimeout ||
          dioError.type == DioExceptionType.sendTimeout ||
          dioError.type == DioExceptionType.receiveTimeout ||
          dioError.type == DioExceptionType.connectionError) {
        return Left(
          ConnectionFailure('TTS connection error: ${dioError.message}'),
        );
      }
      final statusCode = dioError.response?.statusCode;
      return Left(
        ServerFailure(
          'TTS synthesis failed: ${dioError.message ?? "Server error"}',
          statusCode ?? -1,
        ),
      );
    } catch (e) {
      return Left(ServerFailure('TTS request error: $e'));
    }
  }
}

/// Base contract for Voice Output Service.
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

/// Implementation of VoiceOutputService using audioplayers and TTS endpoint.
class VoiceOutputService implements VoiceOutputServiceBase {
  VoiceOutputService({
    AudioPlayerWrapper? player,
    TtsClient? ttsClient,
  })  : _player = player ?? DefaultAudioPlayerWrapper(),
        _ttsClient = ttsClient {
    _initSubscriptions();
  }

  final AudioPlayerWrapper _player;
  final TtsClient? _ttsClient;

  final _statusController = StreamController<VoiceOutputStatus>.broadcast();
  final _errorController = StreamController<String>.broadcast();

  final _audioQueue = <Uint8List>[];
  StringBuffer _streamBuffer = StringBuffer();
  int _playbackEpoch = 0;

  bool _isPlaying = false;
  bool _isMuted = false;
  VoiceOutputStatus _currentStatus = VoiceOutputStatus.idle;

  StreamSubscription<void>? _completeSubscription;
  StreamSubscription<PlayerState>? _stateSubscription;

  void _initSubscriptions() {
    _completeSubscription = _player.onPlayerComplete.listen((_) {
      _playNextInQueue();
    });

    _stateSubscription = _player.onPlayerStateChanged.listen((state) {
      if (state == PlayerState.playing) {
        _isPlaying = true;
        _updateStatus(VoiceOutputStatus.playing);
      } else if (state == PlayerState.paused) {
        _updateStatus(VoiceOutputStatus.paused);
      } else if (state == PlayerState.stopped && _audioQueue.isEmpty) {
        _isPlaying = false;
        _updateStatus(VoiceOutputStatus.idle);
      }
    });
  }

  void _updateStatus(VoiceOutputStatus status) {
    _currentStatus = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  @override
  bool get isPlaying => _isPlaying;

  @override
  bool get isMuted => _isMuted;

  @override
  VoiceOutputStatus get currentStatus => _currentStatus;

  @override
  int get queueLength => _audioQueue.length;

  @override
  Stream<VoiceOutputStatus> get statusStream => _statusController.stream;

  @override
  Stream<String> get errorStream => _errorController.stream;

  @override
  void setMuted(bool muted) {
    _isMuted = muted;
    if (_isMuted) {
      _player.setVolume(0.0);
    } else {
      _player.setVolume(1.0);
    }
  }

  @override
  void toggleMute() {
    setMuted(!_isMuted);
  }

  @override
  Future<Either<Failure, Unit>> queueAudio(Uint8List audioBytes) async {
    if (_isMuted) {
      return const Right(unit);
    }

    if (!_isPlaying) {
      _isPlaying = true;
      _updateStatus(VoiceOutputStatus.playing);
      try {
        await _player.playBytes(audioBytes, volume: _isMuted ? 0.0 : 1.0);
      } catch (e) {
        if (!_errorController.isClosed) {
          _errorController.add('Playback error: $e');
        }
        _updateStatus(VoiceOutputStatus.error);
        await _playNextInQueue();
      }
    } else {
      _audioQueue.add(audioBytes);
    }

    return const Right(unit);
  }

  Future<void> _playNextInQueue() async {
    if (_audioQueue.isEmpty) {
      _isPlaying = false;
      _updateStatus(VoiceOutputStatus.idle);
      return;
    }

    _isPlaying = true;
    _updateStatus(VoiceOutputStatus.playing);
    final nextChunk = _audioQueue.removeAt(0);

    try {
      await _player.playBytes(nextChunk, volume: _isMuted ? 0.0 : 1.0);
    } catch (e) {
      if (!_errorController.isClosed) {
        _errorController.add('Playback error: $e');
      }
      _updateStatus(VoiceOutputStatus.error);
      await _playNextInQueue();
    }
  }

  @override
  Future<Either<Failure, Unit>> speakText(
    String text, {
    String? voice,
    String? model,
    double? speed,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return const Left(ValidationFailure('Text cannot be empty'));
    }

    if (_isMuted) {
      return const Right(unit);
    }

    final tts = _ttsClient;
    if (tts == null) {
      return const Left(ServerFailure('TTS client not configured'));
    }

    final epoch = _playbackEpoch;
    _updateStatus(VoiceOutputStatus.loading);
    final result = await tts.synthesizeSpeech(
      text: trimmed,
      voice: voice,
      model: model,
      speed: speed,
    );

    if (epoch != _playbackEpoch) {
      return const Right(unit);
    }

    return result.fold(
      (failure) {
        if (!_errorController.isClosed) {
          _errorController.add(failure.message);
        }
        _updateStatus(VoiceOutputStatus.error);
        return Left(failure);
      },
      (audioBytes) async {
        return queueAudio(audioBytes);
      },
    );
  }

  @override
  Future<Either<Failure, Unit>> queueText(
    String text, {
    String? voice,
    String? model,
    double? speed,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isMuted) {
      return const Right(unit);
    }

    final tts = _ttsClient;
    if (tts == null) {
      return const Left(ServerFailure('TTS client not configured'));
    }

    final epoch = _playbackEpoch;
    final result = await tts.synthesizeSpeech(
      text: trimmed,
      voice: voice,
      model: model,
      speed: speed,
    );

    if (epoch != _playbackEpoch) {
      return const Right(unit);
    }

    return result.fold(
      (failure) {
        if (!_errorController.isClosed) {
          _errorController.add(failure.message);
        }
        _updateStatus(VoiceOutputStatus.error);
        return Left(failure);
      },
      (audioBytes) async {
        return queueAudio(audioBytes);
      },
    );
  }

  @override
  Future<void> feedStreamingDelta(String delta) async {
    if (_isMuted) return;

    _streamBuffer.write(delta);
    var content = _streamBuffer.toString();

    final sentenceRegex = RegExp(r'([.!?\n]+(?:\s+|$))');
    var match = sentenceRegex.firstMatch(content);
    while (match != null) {
      final sentence = content.substring(0, match.end).trim();
      content = content.substring(match.end);
      _streamBuffer = StringBuffer(content);
      if (sentence.isNotEmpty) {
        await queueText(sentence);
      }
      match = sentenceRegex.firstMatch(content);
    }
  }

  @override
  Future<void> flushStreaming() async {
    if (_isMuted) {
      _streamBuffer.clear();
      return;
    }

    final remaining = _streamBuffer.toString().trim();
    _streamBuffer.clear();
    if (remaining.isNotEmpty) {
      await queueText(remaining);
    }
  }

  @override
  Future<void> pause() async {
    _updateStatus(VoiceOutputStatus.paused);
    await _player.pause();
  }

  @override
  Future<void> resume() async {
    _updateStatus(VoiceOutputStatus.playing);
    await _player.resume();
  }

  @override
  Future<void> stop() async {
    _playbackEpoch++;
    _audioQueue.clear();
    _streamBuffer.clear();
    _isPlaying = false;
    await _player.stop();
    _updateStatus(VoiceOutputStatus.idle);
  }

  @override
  Future<void> interrupt() async {
    _playbackEpoch++;
    _audioQueue.clear();
    _streamBuffer.clear();
    _isPlaying = false;
    try {
      await _player.stop();
    } catch (_) {}
    _updateStatus(VoiceOutputStatus.idle);
  }

  @override
  void dispose() {
    _completeSubscription?.cancel();
    _stateSubscription?.cancel();
    _statusController.close();
    _errorController.close();
    _player.dispose();
  }
}
