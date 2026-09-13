import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/common/exception.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockAudioPlayerWrapper mockPlayer;
  late MockTtsClient mockTtsClient;
  late MockPlatformTtsEngine mockPlatformTts;
  late VoiceOutputService service;

  late StreamController<PlayerState> playerStateController;

  setUpAll(() {
    registerFallbackValue(Uint8List(0));
    registerFallbackValue(BytesSource(Uint8List(0)));
    registerFallbackValue(Options());
  });

  setUp(() {
    mockPlayer = MockAudioPlayerWrapper();
    mockTtsClient = MockTtsClient();
    mockPlatformTts = MockPlatformTtsEngine();

    playerStateController = StreamController<PlayerState>.broadcast();

    when(
      () => mockPlayer.onPlayerStateChanged,
    ).thenAnswer((_) => playerStateController.stream);
    when(() => mockPlayer.setVolume(any())).thenAnswer((_) async {});
    when(() => mockPlayer.play(any())).thenAnswer((_) async {});
    when(() => mockPlayer.stop()).thenAnswer((_) async {});
    when(() => mockPlayer.pause()).thenAnswer((_) async {});
    when(() => mockPlayer.resume()).thenAnswer((_) async {});
    when(() => mockPlayer.dispose()).thenAnswer((_) async {});
    when(() => mockPlatformTts.isAvailable).thenReturn(true);
    when(
      () => mockPlatformTts.speak(
        any(),
        voice: any(named: 'voice'),
        speed: any(named: 'speed'),
      ),
    ).thenAnswer((_) async => true);
    when(() => mockPlatformTts.setVolume(any())).thenAnswer((_) async {});
    when(() => mockPlatformTts.stop()).thenAnswer((_) async {});
    when(
      () => mockTtsClient.isRemoteConfigured(),
    ).thenAnswer((_) async => true);

    service = VoiceOutputService(
      ttsClient: mockTtsClient,
      audioPlayer: mockPlayer,
      platformTts: mockPlatformTts,
    );
  });

  tearDown(() async {
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

      expect(result.isRight(), true);
      expect(service.isPlaying, true);
      expect(service.currentStatus, VoiceOutputStatus.playing);
      verify(() => mockPlayer.play(any(that: isA<BytesSource>()))).called(1);
    });

    test('queueAudio queues second chunk when already playing', () async {
      final bytes1 = Uint8List.fromList([1, 2, 3]);
      final bytes2 = Uint8List.fromList([4, 5, 6]);

      await service.queueAudio(bytes1);
      expect(service.isPlaying, true);
      expect(service.queueLength, 0);

      await service.queueAudio(bytes2);
      expect(service.queueLength, 1);
      verify(() => mockPlayer.play(any(that: isA<BytesSource>()))).called(1);
    });

    test('playing next item automatically when completed state emits',
        () async {
      final bytes1 = Uint8List.fromList([1, 2, 3]);
      final bytes2 = Uint8List.fromList([4, 5, 6]);

      await service.queueAudio(bytes1);
      await service.queueAudio(bytes2);
      expect(service.queueLength, 1);

      playerStateController.add(PlayerState.completed);
      await pumpEventQueue();

      verify(() => mockPlayer.play(any(that: isA<BytesSource>()))).called(2);
      expect(service.queueLength, 0);
      expect(service.isPlaying, true);

      playerStateController.add(PlayerState.completed);
      await pumpEventQueue();

      expect(service.isPlaying, false);
      expect(service.currentStatus, VoiceOutputStatus.idle);
    });

    test('queueAudio still plays at volume 0 when muted', () async {
      service.setMuted(true);
      final bytes = Uint8List.fromList([1, 2, 3]);

      final result = await service.queueAudio(bytes);

      expect(result.isRight(), true);
      expect(service.isPlaying, true);
      verify(() => mockPlayer.play(any(that: isA<BytesSource>()))).called(1);
    });
  });

  group('VoiceOutputService - Barge-In / Interruption Handling', () {
    test('interrupt stops player, clears queue and resets state to stopped',
        () async {
      final bytes1 = Uint8List.fromList([1, 2, 3]);
      final bytes2 = Uint8List.fromList([4, 5, 6]);

      await service.queueAudio(bytes1);
      await service.queueAudio(bytes2);
      expect(service.isPlaying, true);
      expect(service.queueLength, 1);

      await service.interrupt();

      expect(service.isPlaying, false);
      expect(service.queueLength, 0);
      expect(service.currentStatus, VoiceOutputStatus.stopped);
      verify(() => mockPlayer.stop()).called(1);
    });

    test('interrupt while idle is safe and does not throw', () async {
      await expectLater(service.interrupt(), completes);
      expect(service.isPlaying, false);
      expect(service.currentStatus, VoiceOutputStatus.stopped);
    });
  });

  group('VoiceOutputService - Text-to-Speech (TTS)', () {
    test('speakText returns Left(ServerFailure) when text is empty', () async {
      final resultEmpty = await service.speakText('');
      final resultWhitespace = await service.speakText('   \n  ');

      expect(resultEmpty.isLeft(), true);
      expect(resultWhitespace.isLeft(), true);
      resultEmpty.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left(ServerFailure)'),
      );
    });

    test('speakText calls ttsClient and plays synthesized audio', () async {
      final audioBytes = Uint8List.fromList([10, 20, 30]);
      when(
        () => mockTtsClient.synthesize(
          text: 'Hello world',
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer((_) async => audioBytes);

      final result = await service.speakText('Hello world', voice: 'alloy');

      expect(result.isRight(), true);
      verify(
        () => mockTtsClient.synthesize(
          text: 'Hello world',
          voice: 'alloy',
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      ).called(1);
      verify(() => mockPlayer.play(any(that: isA<BytesSource>()))).called(1);
    });

    test('speakText returns Left(Failure) when TTS throws and emits error',
        () async {
      when(
        () => mockTtsClient.synthesize(
          text: any(named: 'text'),
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      ).thenThrow(Exception('TTS quota exceeded'));

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
      when(
        () => mockTtsClient.synthesize(
          text: 'Queued text',
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer((_) async => audioBytes);

      final result = await service.queueText('Queued text');

      expect(result.isRight(), true);
      verify(() => mockPlayer.play(any(that: isA<BytesSource>()))).called(1);
    });
  });

  group('VoiceOutputService - Streaming Delta Chunking', () {
    test('feedStreamingDelta buffers short deltas without synthesizing',
        () async {
      await service.feedStreamingDelta('Hello ');
      await service.feedStreamingDelta('there! ');

      verifyNever(
        () => mockTtsClient.synthesize(
          text: any(named: 'text'),
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      );
    });

    test('feedStreamingDelta synthesizes once buffer passes threshold',
        () async {
      final audio = Uint8List.fromList([1, 1]);
      when(
        () => mockTtsClient.synthesize(
          text: any(named: 'text'),
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer((_) async => audio);

      final longPrefix = List.filled(30, 'word ').join();
      await service.feedStreamingDelta(longPrefix);
      await service.feedStreamingDelta('final sentence. ');

      verify(
        () => mockTtsClient.synthesize(
          text: any(named: 'text'),
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      ).called(1);
    });

    test('flushStreaming synthesizes remaining partial text', () async {
      final audioTail = Uint8List.fromList([9, 9, 9]);
      when(
        () => mockTtsClient.synthesize(
          text: 'Final thoughts without punctuation',
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer((_) async => audioTail);

      await service.feedStreamingDelta('Final thoughts ');
      await service.feedStreamingDelta('without punctuation');
      await service.flushStreaming();

      verify(
        () => mockTtsClient.synthesize(
          text: 'Final thoughts without punctuation',
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      ).called(1);
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

    test('stop calls player.stop, clears queue, and emits stopped', () async {
      final bytes = Uint8List.fromList([1, 2]);
      await service.queueAudio(bytes);

      await service.stop();

      verify(() => mockPlayer.stop()).called(1);
      expect(service.isPlaying, false);
      expect(service.queueLength, 0);
      expect(service.currentStatus, VoiceOutputStatus.stopped);
    });

    test('playback exception on play emits error and continues', () async {
      final badBytes = Uint8List.fromList([99]);

      when(() => mockPlayer.play(any())).thenThrow(Exception('Codec failure'));

      final errors = <String>[];
      final sub = service.errorStream.listen(errors.add);

      await service.queueAudio(badBytes);
      await pumpEventQueue();
      await sub.cancel();

      expect(errors.isNotEmpty, true);
      expect(errors.first, contains('Codec failure'));
      expect(service.isPlaying, false);
    });
  });

  group('DioTtsClient', () {
    late MockDio mockDio;
    late DioTtsClient ttsClient;

    setUp(() {
      mockDio = MockDio();
      ttsClient = DioTtsClient(
        dio: mockDio,
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'sk-test-key',
      );
    });

    test('synthesize returns Uint8List on 200 response', () async {
      final bytes = [1, 2, 3, 4, 5];
      when(
        () => mockDio.post<List<int>>(
          'https://api.openai.com/v1/audio/speech',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<List<int>>(
          data: bytes,
          statusCode: 200,
          requestOptions: RequestOptions(path: '/audio/speech'),
        ),
      );

      final result = await ttsClient.synthesize(text: 'Test TTS', voice: 'nova');

      expect(result, equals(Uint8List.fromList(bytes)));
    });

    test('synthesize throws ServerException on non-200 response', () async {
      when(
        () => mockDio.post<List<int>>(
          'https://api.openai.com/v1/audio/speech',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<List<int>>(
          data: [1],
          statusCode: 401,
          statusMessage: 'Unauthorized',
          requestOptions: RequestOptions(path: '/audio/speech'),
        ),
      );

      await expectLater(
        () => ttsClient.synthesize(text: 'Test TTS'),
        throwsA(isA<ServerException>()),
      );
    });

    test('synthesize propagates DioException on timeout', () async {
      when(
        () => mockDio.post<List<int>>(
          'https://api.openai.com/v1/audio/speech',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/audio/speech'),
          type: DioExceptionType.connectionTimeout,
        ),
      );

      await expectLater(
        () => ttsClient.synthesize(text: 'Test TTS'),
        throwsA(isA<DioException>()),
      );
    });

    test('synthesize uses AppConstants.defaultBaseUrl when baseUrl is empty',
        () async {
      final client = DioTtsClient(dio: mockDio);
      when(
        () => mockDio.post<List<int>>(
          'https://indra-9router.my.id/v1/audio/speech',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<List<int>>(
          data: [1, 2, 3],
          statusCode: 200,
          requestOptions: RequestOptions(path: '/audio/speech'),
        ),
      );

      final result = await client.synthesize(text: 'Hello');
      expect(result, equals(Uint8List.fromList([1, 2, 3])));
    });

    test(
        'synthesize throws UnsupportedEndpointException on 404 DioException',
        () async {
      when(
        () => mockDio.post<List<int>>(
          'https://api.openai.com/v1/audio/speech',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenThrow(
        DioException(
          requestOptions: RequestOptions(path: '/audio/speech'),
          type: DioExceptionType.badResponse,
          response: Response<dynamic>(
            requestOptions: RequestOptions(path: '/audio/speech'),
            statusCode: 404,
          ),
        ),
      );

      await expectLater(
        () => ttsClient.synthesize(text: 'Test TTS'),
        throwsA(isA<UnsupportedEndpointException>()),
      );
    });

    test('synthesize throws UnsupportedEndpointException on 404 response',
        () async {
      when(
        () => mockDio.post<List<int>>(
          'https://api.openai.com/v1/audio/speech',
          data: any(named: 'data'),
          options: any(named: 'options'),
        ),
      ).thenAnswer(
        (_) async => Response<List<int>>(
          data: [1],
          statusCode: 404,
          statusMessage: 'Not Found',
          requestOptions: RequestOptions(path: '/audio/speech'),
        ),
      );

      await expectLater(
        () => ttsClient.synthesize(text: 'Test TTS'),
        throwsA(isA<UnsupportedEndpointException>()),
      );
    });
  });

  group('VoiceOutputService - TTS engine selection & platform fallback', () {
    void stubTtsThrowingUnsupported() {
      when(
        () => mockTtsClient.synthesize(
          text: any(named: 'text'),
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      ).thenThrow(const UnsupportedEndpointException());
    }

    void stubPlatformSpeak(bool result) {
      when(
        () => mockPlatformTts.speak(
          any(),
          voice: any(named: 'voice'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer((_) async => result);
    }

    test('remote 404 falls back to platform TTS', () async {
      stubTtsThrowingUnsupported();
      stubPlatformSpeak(true);

      final statuses = <VoiceOutputStatus>[];
      final statusSub = service.statusStream.listen(statuses.add);

      final result = await service.speakText('Hello');

      await pumpEventQueue();
      await statusSub.cancel();

      expect(result.isRight(), true);
      verify(
        () => mockPlatformTts.speak(
          'Hello',
          voice: any(named: 'voice'),
          speed: any(named: 'speed'),
        ),
      ).called(1);
      expect(service.lastEngineUsed, TtsEngine.androidTts);
      expect(service.currentStatus, VoiceOutputStatus.idle);
      expect(statuses, contains(VoiceOutputStatus.playing));
    });

    test('no remote base URL uses platform directly', () async {
      when(
        () => mockTtsClient.isRemoteConfigured(),
      ).thenAnswer((_) async => false);
      stubPlatformSpeak(true);

      final result = await service.speakText('Hello');

      expect(result.isRight(), true);
      verifyNever(
        () => mockTtsClient.synthesize(
          text: any(named: 'text'),
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      );
      verify(
        () => mockPlatformTts.speak(
          'Hello',
          voice: any(named: 'voice'),
          speed: any(named: 'speed'),
        ),
      ).called(1);
      expect(service.lastEngineUsed, TtsEngine.androidTts);
    });

    test('remote success keeps byte-player path', () async {
      final audioBytes = Uint8List.fromList([1, 2, 3]);
      when(
        () => mockTtsClient.synthesize(
          text: any(named: 'text'),
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer((_) async => audioBytes);

      final result = await service.speakText('Hello');

      expect(result.isRight(), true);
      verify(() => mockPlayer.play(any(that: isA<BytesSource>()))).called(1);
      verifyNever(
        () => mockPlatformTts.speak(
          any(),
          voice: any(named: 'voice'),
          speed: any(named: 'speed'),
        ),
      );
      expect(service.lastEngineUsed, TtsEngine.remoteTts);
    });

    test('both paths fail -> Left', () async {
      stubTtsThrowingUnsupported();
      stubPlatformSpeak(false);

      final result = await service.speakText('Hello');

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left(ServerFailure)'),
      );
      expect(service.currentStatus, VoiceOutputStatus.error);
    });

    test('setMuted parity reaches platform engine', () async {
      service.setMuted(true);
      service.setMuted(false);

      verify(() => mockPlatformTts.setVolume(0.0)).called(1);
      verify(() => mockPlatformTts.setVolume(1.0)).called(1);
    });

    test('stop during platform speech keeps stopped status', () async {
      stubTtsThrowingUnsupported();
      final completer = Completer<bool>();
      when(
        () => mockPlatformTts.speak(
          any(),
          voice: any(named: 'voice'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer((_) => completer.future);

      final resultFuture = service.speakText('Hello');
      await pumpEventQueue();

      await service.stop();
      completer.complete(true);
      final result = await resultFuture;

      expect(result.isRight(), true);
      verify(() => mockPlatformTts.stop()).called(1);
      expect(service.currentStatus, VoiceOutputStatus.stopped);
      expect(service.lastEngineUsed, isNull);
    });
  });
}
