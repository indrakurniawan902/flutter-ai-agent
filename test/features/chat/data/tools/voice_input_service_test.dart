import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/voice_input_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockSpeechToTextWrapper mockWrapper;
  late VoiceInputService service;

  setUpAll(() {
    registerFallbackValue(
      SpeechRecognitionResult([SpeechRecognitionWords('test', null, 0.9)], 1),
    );
    registerFallbackValue(SpeechRecognitionError('error', false));
  });

  setUp(() {
    mockWrapper = MockSpeechToTextWrapper();
    service = VoiceInputService(wrapper: mockWrapper);
  });

  tearDown(() {
    service.dispose();
  });

  group('VoiceInputService - Initialization & Permissions', () {
    test('initialize returns Right(true) when speech recognition is available',
        () async {
      when(() => mockWrapper.initialize(
            onError: any(named: 'onError'),
            onStatus: any(named: 'onStatus'),
          )).thenAnswer((_) async => true);
      when(() => mockWrapper.isAvailable).thenReturn(true);

      final result = await service.initialize();

      expect(result, const Right(true));
      expect(service.isAvailable, true);
    });

    test(
        'initialize returns Left(PermissionFailure) when user denies permission or unavailable',
        () async {
      when(() => mockWrapper.initialize(
            onError: any(named: 'onError'),
            onStatus: any(named: 'onStatus'),
          )).thenAnswer((_) async => false);
      when(() => mockWrapper.isAvailable).thenReturn(false);

      final result = await service.initialize();

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<PermissionFailure>()),
        (_) => fail('Expected Left(PermissionFailure)'),
      );
      expect(service.isAvailable, false);
    });

    test('initialize returns Left(ServerFailure) on exception', () async {
      when(() => mockWrapper.initialize(
            onError: any(named: 'onError'),
            onStatus: any(named: 'onStatus'),
          )).thenThrow(Exception('Microphone init hardware crash'));

      final result = await service.initialize();

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left(ServerFailure)'),
      );
    });

    test('checkPermission returns Right(true) when available', () async {
      when(() => mockWrapper.initialize(
            onError: any(named: 'onError'),
            onStatus: any(named: 'onStatus'),
          )).thenAnswer((_) async => true);
      when(() => mockWrapper.isAvailable).thenReturn(true);

      await service.initialize();
      final result = await service.checkPermission();

      expect(result, const Right(true));
    });

    test('checkPermission returns Left(PermissionFailure) when not available',
        () async {
      when(() => mockWrapper.initialize(
            onError: any(named: 'onError'),
            onStatus: any(named: 'onStatus'),
          )).thenAnswer((_) async => false);
      when(() => mockWrapper.isAvailable).thenReturn(false);

      final result = await service.checkPermission();

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<PermissionFailure>()),
        (_) => fail('Expected PermissionFailure'),
      );
    });
  });

  group('VoiceInputService - Listening & Streaming', () {
    test(
        'startListening auto-initializes and transitions status to listening',
        () async {
      when(() => mockWrapper.initialize(
            onError: any(named: 'onError'),
            onStatus: any(named: 'onStatus'),
          )).thenAnswer((_) async => true);
      when(() => mockWrapper.isAvailable).thenReturn(true);
      when(() => mockWrapper.isListening).thenReturn(true);
      when(() => mockWrapper.listen(
            onResult: any(named: 'onResult'),
            onSoundLevelChange: any(named: 'onSoundLevelChange'),
            listenFor: any(named: 'listenFor'),
            pauseFor: any(named: 'pauseFor'),
            localeId: any(named: 'localeId'),
            partialResults: any(named: 'partialResults'),
          )).thenAnswer((_) async {});

      final statusFuture = expectLater(
        service.statusStream,
        emits(VoiceInputStatus.listening),
      );

      final result = await service.startListening();

      expect(result, const Right(unit));
      expect(service.isListening, true);
      await statusFuture;
      verify(() => mockWrapper.listen(
            onResult: any(named: 'onResult'),
            onSoundLevelChange: any(named: 'onSoundLevelChange'),
          )).called(1);
    });

    test('startListening streams transcribed text when speech result arrives',
        () async {
      void Function(SpeechRecognitionResult result)? onResultCallback;

      when(() => mockWrapper.initialize(
            onError: any(named: 'onError'),
            onStatus: any(named: 'onStatus'),
          )).thenAnswer((_) async => true);
      when(() => mockWrapper.isAvailable).thenReturn(true);
      when(() => mockWrapper.isListening).thenReturn(true);
      when(() => mockWrapper.listen(
            onResult: any(named: 'onResult'),
            onSoundLevelChange: any(named: 'onSoundLevelChange'),
            listenFor: any(named: 'listenFor'),
            pauseFor: any(named: 'pauseFor'),
            localeId: any(named: 'localeId'),
            partialResults: any(named: 'partialResults'),
          )).thenAnswer((invocation) async {
        onResultCallback = invocation.namedArguments[#onResult]
            as void Function(SpeechRecognitionResult);
      });

      await service.startListening();

      expectLater(
        service.transcriptionStream,
        emitsInOrder(['Halo', 'Halo agen Hermes']),
      );

      final result1 = SpeechRecognitionResult(
        [SpeechRecognitionWords('Halo', null, 0.9)],
        0, // interim
      );
      final result2 = SpeechRecognitionResult(
        [SpeechRecognitionWords('Halo agen Hermes', null, 0.95)],
        1, // final
      );

      onResultCallback?.call(result1);
      onResultCallback?.call(result2);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(service.lastRecognizedWords, 'Halo agen Hermes');
    });

    test('startListening streams normalized sound levels', () async {
      void Function(double level)? onSoundLevelCallback;

      when(() => mockWrapper.initialize(
            onError: any(named: 'onError'),
            onStatus: any(named: 'onStatus'),
          )).thenAnswer((_) async => true);
      when(() => mockWrapper.isAvailable).thenReturn(true);
      when(() => mockWrapper.isListening).thenReturn(true);
      when(() => mockWrapper.listen(
            onResult: any(named: 'onResult'),
            onSoundLevelChange: any(named: 'onSoundLevelChange'),
            listenFor: any(named: 'listenFor'),
            pauseFor: any(named: 'pauseFor'),
            localeId: any(named: 'localeId'),
            partialResults: any(named: 'partialResults'),
          )).thenAnswer((invocation) async {
        onSoundLevelCallback = invocation.namedArguments[#onSoundLevelChange]
            as void Function(double);
      });

      await service.startListening();

      expectLater(
        service.soundLevelStream,
        emitsInOrder([
          predicate<double>((v) => v >= 0.0 && v <= 1.0),
          predicate<double>((v) => v >= 0.0 && v <= 1.0),
        ]),
      );

      onSoundLevelCallback?.call(-30.0);
      onSoundLevelCallback?.call(5.0);
    });

    test('final speech recognition marks status as done', () async {
      void Function(SpeechRecognitionResult result)? onResultCallback;

      when(() => mockWrapper.initialize(
            onError: any(named: 'onError'),
            onStatus: any(named: 'onStatus'),
          )).thenAnswer((_) async => true);
      when(() => mockWrapper.isAvailable).thenReturn(true);
      when(() => mockWrapper.isListening).thenReturn(true);
      when(() => mockWrapper.listen(
            onResult: any(named: 'onResult'),
            onSoundLevelChange: any(named: 'onSoundLevelChange'),
            listenFor: any(named: 'listenFor'),
            pauseFor: any(named: 'pauseFor'),
            localeId: any(named: 'localeId'),
            partialResults: any(named: 'partialResults'),
          )).thenAnswer((invocation) async {
        onResultCallback = invocation.namedArguments[#onResult]
            as void Function(SpeechRecognitionResult);
      });

      await service.startListening();

      final statusFuture = expectLater(
        service.statusStream,
        emitsInOrder([
          VoiceInputStatus.done,
        ]),
      );

      final finalResult = SpeechRecognitionResult(
        [SpeechRecognitionWords('Testing selesai', null, 0.98)],
        ResultType.finalResult.value,
      );

      onResultCallback?.call(finalResult);
      await statusFuture;
    });

    test('error callback emits error message and updates status to error',
        () async {
      void Function(SpeechRecognitionError error)? onErrorCallback;

      when(() => mockWrapper.initialize(
            onError: any(named: 'onError'),
            onStatus: any(named: 'onStatus'),
          )).thenAnswer((invocation) async {
        onErrorCallback = invocation.namedArguments[#onError]
            as void Function(SpeechRecognitionError)?;
        return true;
      });
      when(() => mockWrapper.isAvailable).thenReturn(true);
      when(() => mockWrapper.isListening).thenReturn(true);
      when(() => mockWrapper.listen(
            onResult: any(named: 'onResult'),
            onSoundLevelChange: any(named: 'onSoundLevelChange'),
          )).thenAnswer((_) async {});

      await service.startListening();

      expectLater(
        service.errorStream,
        emits('Audio recording hardware error'),
      );
      expectLater(
        service.statusStream,
        emits(VoiceInputStatus.error),
      );

      onErrorCallback
          ?.call(SpeechRecognitionError('Audio recording hardware error', true));
    });
  });

  group('VoiceInputService - Stop and Cancel', () {
    test('stopListening stops speech and returns collected text', () async {
      void Function(SpeechRecognitionResult result)? onResultCallback;

      when(() => mockWrapper.initialize(
            onError: any(named: 'onError'),
            onStatus: any(named: 'onStatus'),
          )).thenAnswer((_) async => true);
      when(() => mockWrapper.isAvailable).thenReturn(true);
      when(() => mockWrapper.isListening).thenReturn(true);
      when(() => mockWrapper.listen(
            onResult: any(named: 'onResult'),
            onSoundLevelChange: any(named: 'onSoundLevelChange'),
          )).thenAnswer((invocation) async {
        onResultCallback = invocation.namedArguments[#onResult]
            as void Function(SpeechRecognitionResult);
      });
      when(() => mockWrapper.stop()).thenAnswer((_) async {});

      await service.startListening();
      onResultCallback?.call(
        SpeechRecognitionResult(
          [SpeechRecognitionWords('Kirim pesan suara', null, 0.9)],
          0,
        ),
      );

      final stopResult = await service.stopListening();

      expect(stopResult, const Right('Kirim pesan suara'));
      verify(() => mockWrapper.stop()).called(1);
    });

    test('cancelListening cancels speech and resets transcription', () async {
      void Function(SpeechRecognitionResult result)? onResultCallback;

      when(() => mockWrapper.initialize(
            onError: any(named: 'onError'),
            onStatus: any(named: 'onStatus'),
          )).thenAnswer((_) async => true);
      when(() => mockWrapper.isAvailable).thenReturn(true);
      when(() => mockWrapper.isListening).thenReturn(true);
      when(() => mockWrapper.listen(
            onResult: any(named: 'onResult'),
            onSoundLevelChange: any(named: 'onSoundLevelChange'),
          )).thenAnswer((invocation) async {
        onResultCallback = invocation.namedArguments[#onResult]
            as void Function(SpeechRecognitionResult);
      });
      when(() => mockWrapper.cancel()).thenAnswer((_) async {});

      await service.startListening();
      onResultCallback?.call(
        SpeechRecognitionResult(
          [SpeechRecognitionWords('Teks yang dibatalkan', null, 0.9)],
          0,
        ),
      );

      expect(service.lastRecognizedWords, 'Teks yang dibatalkan');

      final statusFuture = expectLater(
        service.statusStream,
        emits(VoiceInputStatus.idle),
      );

      await service.cancelListening();

      expect(service.lastRecognizedWords, '');
      await statusFuture;
      verify(() => mockWrapper.cancel()).called(1);
    });
  });
}
