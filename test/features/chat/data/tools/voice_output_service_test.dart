import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/voice_output_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockAudioPlayerWrapper mockPlayer;
  late MockTtsClient mockTtsClient;
  late VoiceOutputService service;

  late StreamController<void> playerCompleteController;
  late StreamController<PlayerState> playerStateController;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
  });

  setUp(() {
    mockPlayer = MockAudioPlayerWrapper();
    mockTtsClient = MockTtsClient();

    playerCompleteController = StreamController<void>.broadcast();
    playerStateController = StreamController<PlayerState>.broadcast();

    when(() => mockPlayer.onPlayerComplete)
        .thenAnswer((_) => playerCompleteController.stream);
    when(() => mockPlayer.onPlayerStateChanged)
        .thenAnswer((_) => playerStateController.stream);
    when(() => mockPlayer.state).thenReturn(PlayerState.stopped);
    when(() => mockPlayer.setVolume(any())).thenAnswer((_) async {});
    when(() => mockPlayer.playBytes(any(), volume: any(named: 'volume')))
        .thenAnswer((_) async {});
    when(() => mockPlayer.stop()).thenAnswer((_) async {});
    when(() => mockPlayer.pause()).thenAnswer((_) async {});
    when(() => mockPlayer.resume()).thenAnswer((_) async {});
    when(() => mockPlayer.dispose()).thenAnswer((_) async {});

    service = VoiceOutputService(
      player: mockPlayer,
      ttsClient: mockTtsClient,
    );
  });

  tearDown(() async {
    await playerCompleteController.close();
    await playerStateController.close();
    service.dispose();
  });

  group('VoiceOutputService - Initialization & Mute Control', () {
    test('initial properties are correct', () {
      expect(service.isMuted, false);
      expect(service.isPlaying, false);
      expect(service.queueLength, 0);
      expect(service.currentStatus, VoiceOutputStatus.idle);
    });

    test('setMuted(true) mutes playback and sets volume to 0.0', () async {
      service.setMuted(true);

      expect(service.isMuted, true);
      verify(() => mockPlayer.setVolume(0.0)).called(1);
    });

    test('setMuted(false) restores playback volume to 1.0', () async {
      service.setMuted(true);
      service.setMuted(false);

      expect(service.isMuted, false);
      verify(() => mockPlayer.setVolume(1.0)).called(1);
    });

    test('toggleMute toggles mute state between true and false', () {
      expect(service.isMuted, false);
      service.toggleMute();
      expect(service.isMuted, true);
      service.toggleMute();
      expect(service.isMuted, false);
    });
  });

  group('VoiceOutputService - Audio Buffer Playback Queue', () {
    test('queueAudio plays first chunk immediately if idle', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);

      final result = await service.queueAudio(bytes);

      expect(result, const Right(unit));
      expect(service.isPlaying, true);
      expect(service.currentStatus, VoiceOutputStatus.playing);
      verify(() => mockPlayer.playBytes(bytes, volume: 1.0)).called(1);
    });

    test('queueAudio queues second chunk when already playing', () async {
      final bytes1 = Uint8List.fromList([1, 2, 3]);
      final bytes2 = Uint8List.fromList([4, 5, 6]);

      await service.queueAudio(bytes1);
      expect(service.isPlaying, true);
      expect(service.queueLength, 0);

      await service.queueAudio(bytes2);
      expect(service.queueLength, 1);
      verify(() => mockPlayer.playBytes(bytes1, volume: 1.0)).called(1);
      verifyNever(() => mockPlayer.playBytes(bytes2, volume: any(named: 'volume')));
    });

    test('playing next item automatically when onPlayerComplete emits', () async {
      final bytes1 = Uint8List.fromList([1, 2, 3]);
      final bytes2 = Uint8List.fromList([4, 5, 6]);

      await service.queueAudio(bytes1);
      await service.queueAudio(bytes2);
      expect(service.queueLength, 1);

      // First chunk completes
      playerCompleteController.add(null);
      await pumpEventQueue();

      verify(() => mockPlayer.playBytes(bytes2, volume: 1.0)).called(1);
      expect(service.queueLength, 0);
      expect(service.isPlaying, true);

      // Second chunk completes
      playerCompleteController.add(null);
      await pumpEventQueue();

      expect(service.isPlaying, false);
      expect(service.currentStatus, VoiceOutputStatus.idle);
    });

    test('queueAudio drops or suppresses playback when muted', () async {
      service.setMuted(true);
      final bytes = Uint8List.fromList([1, 2, 3]);

      final result = await service.queueAudio(bytes);

      expect(result, const Right(unit));
      expect(service.isPlaying, false);
      verifyNever(() => mockPlayer.playBytes(any(), volume: any(named: 'volume')));
    });
  });

  group('VoiceOutputService - Barge-In / Interruption Handling', () {
    test('interrupt stops player, clears queue and resets state to idle', () async {
      final bytes1 = Uint8List.fromList([1, 2, 3]);
      final bytes2 = Uint8List.fromList([4, 5, 6]);

      await service.queueAudio(bytes1);
      await service.queueAudio(bytes2);
      expect(service.isPlaying, true);
      expect(service.queueLength, 1);

      await service.interrupt();

      expect(service.isPlaying, false);
      expect(service.queueLength, 0);
      expect(service.currentStatus, VoiceOutputStatus.idle);
      verify(() => mockPlayer.stop()).called(1);
    });

    test('interrupt while idle is safe and does not throw', () async {
      await expectLater(service.interrupt(), completes);
      expect(service.isPlaying, false);
      expect(service.currentStatus, VoiceOutputStatus.idle);
    });
  });

  group('VoiceOutputService - Text-to-Speech (TTS)', () {
    test('speakText returns Left(ValidationFailure) when text is empty', () async {
      final resultEmpty = await service.speakText('');
      final resultWhitespace = await service.speakText('   \n  ');

      expect(resultEmpty.isLeft(), true);
      expect(resultWhitespace.isLeft(), true);
      resultEmpty.fold(
        (failure) => expect(failure, isA<ValidationFailure>()),
        (_) => fail('Expected Left(ValidationFailure)'),
      );
    });

    test('speakText calls ttsClient and plays synthesized audio', () async {
      final audioBytes = Uint8List.fromList([10, 20, 30]);
      when(() => mockTtsClient.synthesizeSpeech(
            text: 'Hello world',
            voice: any(named: 'voice'),
            model: any(named: 'model'),
            speed: any(named: 'speed'),
          )).thenAnswer((_) async => Right(audioBytes));

      final result = await service.speakText('Hello world', voice: 'alloy');

      expect(result, const Right(unit));
      verify(() => mockTtsClient.synthesizeSpeech(
            text: 'Hello world',
            voice: 'alloy',
            model: any(named: 'model'),
            speed: any(named: 'speed'),
          )).called(1);
      verify(() => mockPlayer.playBytes(audioBytes, volume: 1.0)).called(1);
    });

    test('speakText returns Left(Failure) when TTS fails and emits to errorStream',
        () async {
      when(() => mockTtsClient.synthesizeSpeech(
            text: any(named: 'text'),
            voice: any(named: 'voice'),
            model: any(named: 'model'),
            speed: any(named: 'speed'),
          )).thenAnswer(
        (_) async => const Left(ServerFailure('TTS quota exceeded')),
      );

      final errors = <String>[];
      final sub = service.errorStream.listen(errors.add);

      final result = await service.speakText('Error text');

      await pumpEventQueue();
      await sub.cancel();

      expect(result.isLeft(), true);
      expect(errors.isNotEmpty, true);
      expect(errors.first, contains('TTS quota exceeded'));
      expect(service.currentStatus, VoiceOutputStatus.error);
    });

    test('queueText synthesizes speech and queues audio chunk', () async {
      final audioBytes = Uint8List.fromList([7, 8, 9]);
      when(() => mockTtsClient.synthesizeSpeech(
            text: 'Queued text',
            voice: any(named: 'voice'),
            model: any(named: 'model'),
            speed: any(named: 'speed'),
          )).thenAnswer((_) async => Right(audioBytes));

      final result = await service.queueText('Queued text');

      expect(result, const Right(unit));
      verify(() => mockPlayer.playBytes(audioBytes, volume: 1.0)).called(1);
    });
  });

  group('VoiceOutputService - Streaming Delta Chunking', () {
    test('feedStreamingDelta buffers and synthesizes sentences on boundary', () async {
      final audio1 = Uint8List.fromList([1, 1]);
      final audio2 = Uint8List.fromList([2, 2]);

      when(() => mockTtsClient.synthesizeSpeech(
            text: 'Hello there!',
            voice: any(named: 'voice'),
            model: any(named: 'model'),
            speed: any(named: 'speed'),
          )).thenAnswer((_) async => Right(audio1));

      when(() => mockTtsClient.synthesizeSpeech(
            text: 'How are you today?',
            voice: any(named: 'voice'),
            model: any(named: 'model'),
            speed: any(named: 'speed'),
          )).thenAnswer((_) async => Right(audio2));

      await service.feedStreamingDelta('Hello ');
      await service.feedStreamingDelta('there! ');

      verify(() => mockTtsClient.synthesizeSpeech(
            text: 'Hello there!',
            voice: any(named: 'voice'),
            model: any(named: 'model'),
            speed: any(named: 'speed'),
          )).called(1);

      await service.feedStreamingDelta('How are you today? ');
      verify(() => mockTtsClient.synthesizeSpeech(
            text: 'How are you today?',
            voice: any(named: 'voice'),
            model: any(named: 'model'),
            speed: any(named: 'speed'),
          )).called(1);
    });

    test('flushStreaming synthesizes remaining partial text', () async {
      final audioTail = Uint8List.fromList([9, 9, 9]);

      when(() => mockTtsClient.synthesizeSpeech(
            text: 'Final thoughts without punctuation',
            voice: any(named: 'voice'),
            model: any(named: 'model'),
            speed: any(named: 'speed'),
          )).thenAnswer((_) async => Right(audioTail));

      await service.feedStreamingDelta('Final thoughts ');
      await service.feedStreamingDelta('without punctuation');
      await service.flushStreaming();

      verify(() => mockTtsClient.synthesizeSpeech(
            text: 'Final thoughts without punctuation',
            voice: any(named: 'voice'),
            model: any(named: 'model'),
            speed: any(named: 'speed'),
          )).called(1);
    });
  });

  group('VoiceOutputService - Pause, Resume, Stop & Error Handling', () {
    test('pause calls player.pause and emits paused status', () async {
      final bytes = Uint8List.fromList([1, 2]);
      await service.queueAudio(bytes);

      await service.pause();

      verify(() => mockPlayer.pause()).called(1);
      expect(service.currentStatus, VoiceOutputStatus.paused);
    });

    test('resume calls player.resume and emits playing status', () async {
      final bytes = Uint8List.fromList([1, 2]);
      await service.queueAudio(bytes);
      await service.pause();

      await service.resume();

      verify(() => mockPlayer.resume()).called(1);
      expect(service.currentStatus, VoiceOutputStatus.playing);
    });

    test('stop calls player.stop, clears queue, and emits idle', () async {
      final bytes = Uint8List.fromList([1, 2]);
      await service.queueAudio(bytes);

      await service.stop();

      verify(() => mockPlayer.stop()).called(1);
      expect(service.isPlaying, false);
      expect(service.queueLength, 0);
      expect(service.currentStatus, VoiceOutputStatus.idle);
    });

    test('playback exception on playBytes emits errorStream and continues', () async {
      final badBytes = Uint8List.fromList([99]);
      final goodBytes = Uint8List.fromList([100]);

      when(() => mockPlayer.playBytes(badBytes, volume: any(named: 'volume')))
          .thenThrow(Exception('Codec decode failure'));

      final errors = <String>[];
      final sub = service.errorStream.listen(errors.add);

      await service.queueAudio(badBytes);
      await service.queueAudio(goodBytes);

      await pumpEventQueue();
      await sub.cancel();

      expect(errors.isNotEmpty, true);
      expect(errors.first, contains('Codec decode failure'));
    });
  });

  group('DioTtsClient', () {
    late MockDio mockDio;
    late DioTtsClient ttsClient;

    setUp(() {
      mockDio = MockDio();
      ttsClient = DioTtsClient(
        dio: mockDio,
        getBaseUrl: () async => 'https://api.openai.com/v1',
        getApiKey: () async => 'sk-test-key',
      );
    });

    test('synthesizeSpeech returns Right(Uint8List) on 200 response', () async {
      final bytes = [1, 2, 3, 4, 5];
      when(() => mockDio.post<List<int>>(
            'https://api.openai.com/v1/audio/speech',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => Response<List<int>>(
            data: bytes,
            statusCode: 200,
            requestOptions: RequestOptions(path: '/audio/speech'),
          ));

      final result = await ttsClient.synthesizeSpeech(
        text: 'Test TTS',
        voice: 'nova',
      );

      expect(result.isRight(), true);
      result.fold(
        (failure) => fail('Expected Right(Uint8List)'),
        (data) => expect(data, equals(bytes)),
      );
    });

    test('synthesizeSpeech returns Left(ServerFailure) on 401 response', () async {
      when(() => mockDio.post<List<int>>(
            'https://api.openai.com/v1/audio/speech',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/audio/speech'),
          response: Response(
            statusCode: 401,
            data: {'error': 'Invalid API Key'},
            requestOptions: RequestOptions(path: '/audio/speech'),
          ),
          type: DioExceptionType.badResponse,
        ),
      );

      final result = await ttsClient.synthesizeSpeech(text: 'Test TTS');

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left(ServerFailure)'),
      );
    });

    test('synthesizeSpeech returns Left(ConnectionFailure) on timeout', () async {
      when(() => mockDio.post<List<int>>(
            'https://api.openai.com/v1/audio/speech',
            data: any(named: 'data'),
            options: any(named: 'options'),
          )).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/audio/speech'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      final result = await ttsClient.synthesizeSpeech(text: 'Test TTS');

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ConnectionFailure>()),
        (_) => fail('Expected Left(ConnectionFailure)'),
      );
    });
  });
}
