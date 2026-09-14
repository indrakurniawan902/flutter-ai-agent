import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDispatcher implements VoicePromptDispatcherBase {
  _FakeDispatcher(this.transportId, {bool ready = true}) : _ready = ready;

  @override
  final String transportId;

  bool _ready;
  int cancelled = 0;

  set ready(bool value) => _ready = value;

  @override
  bool get isReady => _ready;

  @override
  bool get speaksReply => false;

  @override
  Future<Either<Failure, String>> dispatch(String prompt) async =>
      Right(prompt);

  @override
  Future<void> cancel() async {
    cancelled++;
  }
}

void main() {
  late VoicePromptDispatcherRegistry registry;

  setUp(() {
    // Arrange
    registry = VoicePromptDispatcherRegistry();
  });

  test('active is null when nothing is registered', () {
    // Act
    final active = registry.active;

    // Assert
    expect(active, isNull);
    expect(registry.hasReadyTransport, isFalse);
  });

  test('newest registered READY dispatcher wins', () {
    // Arrange
    final a = _FakeDispatcher('a');
    final b = _FakeDispatcher('b');
    registry.register(a);
    registry.register(b);

    // Act
    final active = registry.active;

    // Assert
    expect(active, same(b));
  });

  test('not-ready newest entry falls back to the older ready one', () {
    // Arrange
    final a = _FakeDispatcher('a');
    final b = _FakeDispatcher('b', ready: false);
    registry.register(a);
    registry.register(b);

    // Act
    final active = registry.active;

    // Assert
    expect(active, same(a));
  });

  test('unregister removes entry and re-exposes the previous one', () {
    // Arrange
    final a = _FakeDispatcher('a');
    final b = _FakeDispatcher('b');
    registry.register(a);
    registry.register(b);

    // Act
    registry.unregister('b');

    // Assert
    expect(registry.active, same(a));
  });

  test('hasReadyTransport mirrors active != null', () {
    // Arrange
    final a = _FakeDispatcher('a', ready: false);
    registry.register(a);

    // Act + Assert
    expect(registry.active, isNull);
    expect(registry.hasReadyTransport, isFalse);

    a.ready = true;
    expect(registry.active, same(a));
    expect(registry.hasReadyTransport, isTrue);

    registry.clear();
    expect(registry.active, isNull);
    expect(registry.hasReadyTransport, isFalse);
  });
}
