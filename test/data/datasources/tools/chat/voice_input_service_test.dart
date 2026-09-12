import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockSpeechToTextWrapper mockWrapper;
  late VoiceInputService service;

  setUp(() {
    mockWrapper = MockSpeechToTextWrapper();
    when(() => mockWrapper.cancel()).thenAnswer((_) async {});
    service = VoiceInputService(speech: mockWrapper);
  });

  tearDown(() {
    service.dispose();
  });

  group('VoiceInputService - Initialization & Permissions', () {
    test('initialize returns Right(true) when wrapper initializes', () async {
      when(
        () => mockWrapper.initialize(
          onError: any(named: 'onError'),
          onStatus: any(named: 'onStatus'),
        ),
      ).thenAnswer((_) async => true);
      when(() => mockWrapper.isAvailable).thenReturn(true);

      final result = await service.initialize();

      expect(result, const Right<Failure, bool>(true));
      expect(service.isAvailable, true);
    });

    test('initialize returns Right(false) when wrapper unavailable', () async {
      when(
        () => mockWrapper.initialize(
          onError: any(named: 'onError'),
          onStatus: any(named: 'onStatus'),
        ),
      ).thenAnswer((_) async => false);
      when(() => mockWrapper.isAvailable).thenReturn(false);

      final result = await service.initialize();

      expect(result, const Right<Failure, bool>(false));
      expect(service.isAvailable, false);
    });

    test('initialize returns Left(ServerFailure) on exception', () async {
      when(
        () => mockWrapper.initialize(
          onError: any(named: 'onError'),
          onStatus: any(named: 'onStatus'),
        ),
      ).thenThrow(Exception('Microphone init hardware crash'));

      final result = await service.initialize();

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left(ServerFailure)'),
      );
    });

    test('checkPermission returns Right(hasPermission value)', () async {
      when(() => mockWrapper.hasPermission()).thenAnswer((_) async => true);

      final result = await service.checkPermission();

      expect(result, const Right<Failure, bool>(true));
    });

    test('checkPermission returns Left(PermissionFailure) on exception',
        () async {
      when(
        () => mockWrapper.hasPermission(),
      ).thenThrow(Exception('permission query failed'));

      final result = await service.checkPermission();

      expect(result.isLeft(), true);
      result.fold(
        (failure) => expect(failure, isA<PermissionFailure>()),
        (_) => fail('Expected PermissionFailure'),
      );
    });
  });

  group('VoiceInputService - Listening & Streaming', () {
    test('startListening transitions status to listening', () async {
      when(
        () => mockWrapper.listen(
          onResult: any(named: 'onResult'),
          onSoundLevelChange: any(named: 'onSoundLevelChange'),
          listenFor: any(named: 'listenFor'),
          pauseFor: any(named: 'pauseFor'),
          localeId: any(named: 'localeId'),
        ),
      ).thenAnswer((_) async {});

      final statusFuture = expectLater(
        service.statusStream,
        emits(VoiceInputStatus.listening),
      );

      final result = await service.startListening();

      expect(result, const Right<Failure, Unit>(unit));
      expect(service.isListening, true);
      await statusFuture;
      verify(
        () => mockWrapper.listen(
          onResult: any(named: 'onResult'),
          onSoundLevelChange: any(named: 'onSoundLevelChange'),
        ),
      ).called(1);
    });

    test('startListening returns Left(ServerFailure) when listen throws',
        () async {
      when(
        () => mockWrapper.listen(
          onResult: any(named: 'onResult'),
          onSoundLevelChange: any(named: 'onSoundLevelChange'),
          listenFor: any(named: 'listenFor'),
          pauseFor: any(named: 'pauseFor'),
          localeId: any(named: 'localeId'),
        ),
      ).thenThrow(Exception('listen failed'));

      final result = await service.startListening();

      expect(result.isLeft(), true);
      expect(service.isListening, false);
    });

    test('startListening streams transcribed text when result arrives',
        () async {
      void Function(SpeechRecognitionResult result)? onResultCallback;

      when(
        () => mockWrapper.listen(
          onResult: any(named: 'onResult'),
          onSoundLevelChange: any(named: 'onSoundLevelChange'),
          listenFor: any(named: 'listenFor'),
          pauseFor: any(named: 'pauseFor'),
          localeId: any(named: 'localeId'),
        ),
      ).thenAnswer((invocation) async {
        onResultCallback =
            invocation.namedArguments[#onResult]
                as void Function(SpeechRecognitionResult)?;
      });

      await service.startListening();

      expectLater(
        service.transcriptionStream,
        emitsInOrder(['Halo', 'Halo agen Hermes']),
      );

      final result1 = SpeechRecognitionResult(
        [SpeechRecognitionWords('Halo', null, 0.9)],
        0,
      );
      final result2 = SpeechRecognitionResult(
        [SpeechRecognitionWords('Halo agen Hermes', null, 0.95)],
        1,
      );

      onResultCallback?.call(result1);
      onResultCallback?.call(result2);

      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(service.lastRecognizedWords, 'Halo agen Hermes');
    });

    test('startListening streams normalized sound levels clamped 0..1',
        () async {
      void Function(double level)? onSoundLevelCallback;

      when(
        () => mockWrapper.listen(
          onResult: any(named: 'onResult'),
          onSoundLevelChange: any(named: 'onSoundLevelChange'),
          listenFor: any(named: 'listenFor'),
          pauseFor: any(named: 'pauseFor'),
          localeId: any(named: 'localeId'),
        ),
      ).thenAnswer((invocation) async {
        onSoundLevelCallback =
            invocation.namedArguments[#onSoundLevelChange]
                as void Function(double)?;
      });

      await service.startListening();

      expectLater(
        service.soundLevelStream,
        emitsInOrder([
          predicate<double>((v) => v >= 0.0 && v <= 1.0),
          predicate<double>((v) => v >= 0.0 && v <= 1.0),
        ]),
      );

      onSoundLevelCallback?.call(0.85);
      onSoundLevelCallback?.call(5.0);
    });

    test('normalizeSoundLevel clamps NaN and out-of-range values', () {
      expect(VoiceInputService.normalizeSoundLevel(double.nan), 0.0);
      expect(VoiceInputService.normalizeSoundLevel(-0.5), 0.0);
      expect(VoiceInputService.normalizeSoundLevel(1.5), 1.0);
      expect(VoiceInputService.normalizeSoundLevel(0.42), 0.42);
    });

    test('status callback maps listening/done/notListening', () async {
      void Function(String status)? onStatusCallback;

      when(
        () => mockWrapper.initialize(
          onError: any(named: 'onError'),
          onStatus: any(named: 'onStatus'),
        ),
      ).thenAnswer((invocation) async {
        onStatusCallback =
            invocation.namedArguments[#onStatus] as void Function(String)?;
        return true;
      });

      await service.initialize();

      final statusFuture = expectLater(
        service.statusStream,
        emitsInOrder([
          VoiceInputStatus.listening,
          VoiceInputStatus.done,
          VoiceInputStatus.idle,
        ]),
      );

      onStatusCallback?.call('listening');
      onStatusCallback?.call('done');
      onStatusCallback?.call('notListening');
      await statusFuture;
    });

    test('error callback emits error message and updates status to error',
        () async {
      void Function(SpeechRecognitionError error)? onErrorCallback;

      when(
        () => mockWrapper.initialize(
          onError: any(named: 'onError'),
          onStatus: any(named: 'onStatus'),
        ),
      ).thenAnswer((invocation) async {
        onErrorCallback =
            invocation.namedArguments[#onError]
                as void Function(SpeechRecognitionError)?;
        return true;
      });

      await service.initialize();

      expectLater(
        service.errorStream,
        emits('Audio recording hardware error'),
      );
      expectLater(service.statusStream, emits(VoiceInputStatus.error));

      onErrorCallback?.call(
        SpeechRecognitionError('Audio recording hardware error', true),
      );
    });
  });

  group('VoiceInputService - Stop and Cancel', () {
    test('stopListening stops speech and returns collected text', () async {
      void Function(SpeechRecognitionResult result)? onResultCallback;

      when(
        () => mockWrapper.listen(
          onResult: any(named: 'onResult'),
          onSoundLevelChange: any(named: 'onSoundLevelChange'),
          listenFor: any(named: 'listenFor'),
          pauseFor: any(named: 'pauseFor'),
          localeId: any(named: 'localeId'),
        ),
      ).thenAnswer((invocation) async {
        onResultCallback =
            invocation.namedArguments[#onResult]
                as void Function(SpeechRecognitionResult)?;
      });
      when(() => mockWrapper.stop()).thenAnswer((_) async {});
      when(() => mockWrapper.lastRecognizedWords).thenReturn('');

      await service.startListening();
      onResultCallback?.call(
        SpeechRecognitionResult(
          [SpeechRecognitionWords('Kirim pesan suara', null, 0.9)],
          0,
        ),
      );

      final stopResult = await service.stopListening();

      expect(stopResult, const Right<Failure, String>('Kirim pesan suara'));
      expect(service.isListening, false);
      verify(() => mockWrapper.stop()).called(1);
    });

    test('stopListening prefers plugin lastRecognizedWords when non-empty',
        () async {
      when(
        () => mockWrapper.listen(
          onResult: any(named: 'onResult'),
          onSoundLevelChange: any(named: 'onSoundLevelChange'),
          listenFor: any(named: 'listenFor'),
          pauseFor: any(named: 'pauseFor'),
          localeId: any(named: 'localeId'),
        ),
      ).thenAnswer((_) async {});
      when(() => mockWrapper.stop()).thenAnswer((_) async {});
      when(
        () => mockWrapper.lastRecognizedWords,
      ).thenReturn('Plugin words');

      await service.startListening();
      final stopResult = await service.stopListening();

      expect(stopResult, const Right<Failure, String>('Plugin words'));
    });

    test('cancelListening cancels speech and resets status to idle', () async {
      when(
        () => mockWrapper.listen(
          onResult: any(named: 'onResult'),
          onSoundLevelChange: any(named: 'onSoundLevelChange'),
          listenFor: any(named: 'listenFor'),
          pauseFor: any(named: 'pauseFor'),
          localeId: any(named: 'localeId'),
        ),
      ).thenAnswer((_) async {});
      when(() => mockWrapper.cancel()).thenAnswer((_) async {});

      await service.startListening();
      expect(service.isListening, true);

      final statusFuture = expectLater(
        service.statusStream,
        emits(VoiceInputStatus.idle),
      );

      await service.cancelListening();

      expect(service.isListening, false);
      await statusFuture;
      verify(() => mockWrapper.cancel()).called(1);
    });
  });
}
