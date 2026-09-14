import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/services/voice/voice_turn_service.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_turn_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

class _RecordingDispatcher implements VoicePromptDispatcherBase {
  _RecordingDispatcher();

  final List<String> dispatched = [];
  String reply = 'done';
  Failure? failure;

  @override
  String get transportId => 'fake';

  @override
  bool get isReady => true;

  @override
  Future<Either<Failure, String>> dispatch(String prompt) async {
    if (failure != null) {
      return Left(failure!);
    }
    dispatched.add(prompt);
    return Right(reply);
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  setUpAll(() {
    registerFallbackValue('');
    registerFallbackValue(const Duration(seconds: 1));
  });

  late MockVoiceInputService mockVoiceInput;
  late MockVoiceOutputService mockVoiceOutput;
  late VoicePromptDispatcherRegistry registry;
  late _RecordingDispatcher dispatcher;
  late VoiceTurnService service;
  late StreamController<VoiceInputStatus> statusController;
  late StreamController<String> errorController;

  setUp(() {
    mockVoiceInput = MockVoiceInputService();
    mockVoiceOutput = MockVoiceOutputService();
    registry = VoicePromptDispatcherRegistry();
    dispatcher = _RecordingDispatcher();
    registry.register(dispatcher);
    service = VoiceTurnService(
      voiceInput: mockVoiceInput,
      voiceOutput: mockVoiceOutput,
      registry: registry,
    );
    statusController = StreamController<VoiceInputStatus>.broadcast();
    errorController = StreamController<String>.broadcast();

    // Arrange: stub every getter/stream the service touches.
    when(() => mockVoiceInput.isListening).thenReturn(false);
    when(() => mockVoiceInput.isAvailable).thenReturn(true);
    when(() => mockVoiceInput.lastRecognizedWords).thenReturn('');
    when(() => mockVoiceInput.statusStream)
        .thenAnswer((_) => statusController.stream);
    when(() => mockVoiceInput.errorStream)
        .thenAnswer((_) => errorController.stream);
    when(() => mockVoiceInput.checkPermission())
        .thenAnswer((_) async => const Right(true));
    when(() => mockVoiceInput.initialize())
        .thenAnswer((_) async => const Right(true));
    when(
      () => mockVoiceInput.startListening(
        listenFor: any(named: 'listenFor'),
        pauseFor: any(named: 'pauseFor'),
        localeId: any(named: 'localeId'),
      ),
    ).thenAnswer((_) async => const Right(unit));
    when(() => mockVoiceInput.stopListening())
        .thenAnswer((_) async => const Right('turn on the light'));
    when(() => mockVoiceInput.cancelListening()).thenAnswer((_) async {});

    when(() => mockVoiceOutput.isMuted).thenReturn(false);
    when(() => mockVoiceOutput.interrupt()).thenAnswer((_) async {});
    when(
      () => mockVoiceOutput.speakText(
        any(),
        voice: any(named: 'voice'),
        model: any(named: 'model'),
        speed: any(named: 'speed'),
      ),
    ).thenAnswer((_) async => const Right(unit));
  });

  tearDown(() async {
    service.dispose();
    await statusController.close();
    await errorController.close();
  });

  Future<Either<Failure, VoiceTurnResult>> startTurn() async {
    final future = service.runTurn();
    await Future<void>.delayed(Duration.zero);
    statusController.add(VoiceInputStatus.done);
    return future;
  }

  test('happy path returns result with transcript, reply and spoken true',
      () async {
    // Act
    final result = await startTurn();

    // Assert
    expect(
      result,
      const Right<Failure, VoiceTurnResult>(
        VoiceTurnResult(
          transcript: 'turn on the light',
          reply: 'done',
          spoken: true,
          transportId: 'fake',
        ),
      ),
    );
    verifyInOrder([
      () => mockVoiceOutput.interrupt(),
      () => mockVoiceInput.startListening(
            listenFor: any(named: 'listenFor'),
            pauseFor: any(named: 'pauseFor'),
            localeId: any(named: 'localeId'),
          ),
    ]);
    expect(dispatcher.dispatched, ['turn on the light']);
    verify(() => mockVoiceOutput.speakText('done')).called(1);
  });

  test('mic denied via Right(false) returns PermissionFailure without mic use',
      () async {
    // Arrange
    when(() => mockVoiceInput.checkPermission())
        .thenAnswer((_) async => const Right(false));

    // Act
    final result = await service.runTurn();

    // Assert
    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(failure, isA<PermissionFailure>()),
      (_) => fail('expected Left'),
    );
    verifyNever(
      () => mockVoiceInput.startListening(
        listenFor: any(named: 'listenFor'),
        pauseFor: any(named: 'pauseFor'),
        localeId: any(named: 'localeId'),
      ),
    );
    expect(dispatcher.dispatched, isEmpty);
    verifyNever(() => mockVoiceOutput.speakText(any()));
  });

  test('mic denied via Left returns the same failure instance', () async {
    // Arrange
    const failure = PermissionFailure('nope');
    when(() => mockVoiceInput.checkPermission())
        .thenAnswer((_) async => const Left(failure));

    // Act
    final result = await service.runTurn();

    // Assert
    final returned = result.fold((l) => l, (_) => null);
    expect(identical(returned, failure), isTrue);
    verifyNever(
      () => mockVoiceInput.startListening(
        listenFor: any(named: 'listenFor'),
        pauseFor: any(named: 'pauseFor'),
        localeId: any(named: 'localeId'),
      ),
    );
  });

  test('empty STT returns VoiceTurnEmptyFailure without dispatching',
      () async {
    // Arrange
    when(() => mockVoiceInput.stopListening())
        .thenAnswer((_) async => const Right(''));
    when(() => mockVoiceInput.lastRecognizedWords).thenReturn('');

    // Act
    final result = await startTurn();

    // Assert
    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(failure, isA<VoiceTurnEmptyFailure>()),
      (_) => fail('expected Left'),
    );
    expect(dispatcher.dispatched, isEmpty);
  });

  test('muted output returns unspoken result without speakText', () async {
    // Arrange
    when(() => mockVoiceOutput.isMuted).thenReturn(true);

    // Act
    final result = await startTurn();

    // Assert
    expect(result.isRight(), isTrue);
    result.fold(
      (_) => fail('expected Right'),
      (turn) => expect(turn.spoken, isFalse),
    );
    verifyNever(() => mockVoiceOutput.speakText(any()));
  });

  test('single-flight guard rejects a concurrent runTurn', () async {
    // Act: start a turn without completing it, then run again.
    final first = service.runTurn();
    await Future<void>.delayed(Duration.zero);
    final second = await service.runTurn();

    // Assert
    expect(second.isLeft(), isTrue);
    second.fold(
      (failure) => expect(failure, isA<VoiceTurnBusyFailure>()),
      (_) => fail('expected Left'),
    );
    verify(
      () => mockVoiceInput.startListening(
        listenFor: any(named: 'listenFor'),
        pauseFor: any(named: 'pauseFor'),
        localeId: any(named: 'localeId'),
      ),
    ).called(1);

    // Act: finish the first turn.
    statusController.add(VoiceInputStatus.done);
    final firstResult = await first;

    // Assert
    expect(firstResult.isRight(), isTrue);
  });

  test('no transport returns VoiceTurnNoTransportFailure before mic opens',
      () async {
    // Arrange
    final emptyRegistry = VoicePromptDispatcherRegistry();
    final transportless = VoiceTurnService(
      voiceInput: mockVoiceInput,
      voiceOutput: mockVoiceOutput,
      registry: emptyRegistry,
    );
    addTearDown(transportless.dispose);

    // Act
    final result = await transportless.runTurn();

    // Assert
    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(failure, isA<VoiceTurnNoTransportFailure>()),
      (_) => fail('expected Left'),
    );
    verifyNever(() => mockVoiceInput.checkPermission());
  });

  test('STT error status returns ServerFailure and cancels listening',
      () async {
    // Act
    final future = service.runTurn();
    await Future<void>.delayed(Duration.zero);
    errorController.add('mic broke');
    await Future<void>.delayed(Duration.zero);
    statusController.add(VoiceInputStatus.error);
    final result = await future;

    // Assert
    expect(result.isLeft(), isTrue);
    result.fold(
      (failure) => expect(failure, isA<ServerFailure>()),
      (_) => fail('expected Left'),
    );
    verify(() => mockVoiceInput.cancelListening()).called(1);
  });

  test('phase stream emits listening, dispatching, speaking, done in order',
      () async {
    // Arrange
    final phases = <VoiceTurnPhase>[];
    final sub = service.phaseStream.listen(phases.add);

    // Act
    final result = await startTurn();
    await Future<void>.delayed(Duration.zero);
    await sub.cancel();

    // Assert
    expect(result.isRight(), isTrue);
    expect(
      phases,
      containsAllInOrder([
        VoiceTurnPhase.listening,
        VoiceTurnPhase.dispatching,
        VoiceTurnPhase.speaking,
        VoiceTurnPhase.done,
      ]),
    );
    expect(
      phases.indexOf(VoiceTurnPhase.listening),
      lessThan(phases.indexOf(VoiceTurnPhase.dispatching)),
    );
    expect(
      phases.indexOf(VoiceTurnPhase.dispatching),
      lessThan(phases.indexOf(VoiceTurnPhase.speaking)),
    );
    expect(
      phases.indexOf(VoiceTurnPhase.speaking),
      lessThan(phases.indexOf(VoiceTurnPhase.done)),
    );
  });
}
