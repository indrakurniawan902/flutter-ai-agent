import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_ai_agent/domain/entities/share/shared_payload.dart';
import 'package:flutter_ai_agent/domain/services/share/share_target_service.dart';
import 'package:flutter_ai_agent/presentation/screen/share/cubit/share_target_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/share/cubit/share_target_state.dart';

class MockShareTargetService extends Mock implements ShareTargetService {}

void main() {
  late MockShareTargetService service;

  setUpAll(() {
    registerFallbackValue(<SharedPayload>[]);
  });

  setUp(() {
    service = MockShareTargetService();
    when(() => service.payloadStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => service.startListening()).thenAnswer((_) async {});
    when(() => service.getInitialPayloads()).thenAnswer((_) async => []);
    when(() => service.reset()).thenAnswer((_) async {});
    when(() => service.buildSuggestedPrompt(any())).thenAnswer(
      (inv) => SharedPayload.buildSuggestedPrompt(
        inv.positionalArguments[0] as List<SharedPayload>,
      ),
    );
  });

  ShareTargetCubit buildCubit() => ShareTargetCubit(service: service);

  const textPayload = SharedPayload(
    kind: SharedPayloadKind.text,
    value: 'hello world',
  );
  const urlPayload = SharedPayload(
    kind: SharedPayloadKind.url,
    value: 'https://example.com',
  );

  group('ShareTargetCubit', () {
    test('initial state is ShareTargetInitial', () {
      final cubit = buildCubit();
      expect(cubit.state, isA<ShareTargetInitial>());
      cubit.close();
    });

    blocTest<ShareTargetCubit, ShareTargetState>(
      'init emits Listening when no initial payloads',
      build: buildCubit,
      act: (cubit) => cubit.init(),
      expect: () => [isA<ShareTargetListening>()],
      verify: (_) {
        verify(() => service.startListening()).called(1);
        verify(() => service.getInitialPayloads()).called(1);
      },
    );

    blocTest<ShareTargetCubit, ShareTargetState>(
      'init emits Listening then Received when initial payloads exist',
      build: () {
        when(() => service.getInitialPayloads())
            .thenAnswer((_) async => [textPayload]);
        return buildCubit();
      },
      act: (cubit) => cubit.init(),
      expect: () => [
        isA<ShareTargetListening>(),
        predicate<ShareTargetState>(
          (s) =>
              s is ShareTargetReceived &&
              s.payloads.length == 1 &&
              s.payloads.first.value == 'hello world' &&
              s.suggestedPrompt.contains('hello world'),
        ),
      ],
    );

    test('live payload arriving after init emits Received', () async {
      final controller = StreamController<List<SharedPayload>>();
      when(() => service.payloadStream)
          .thenAnswer((_) => controller.stream);
      final cubit = buildCubit();
      await cubit.init();
      expect(cubit.state, isA<ShareTargetListening>());

      controller.add([urlPayload]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cubit.state, isA<ShareTargetReceived>());
      final received = cubit.state as ShareTargetReceived;
      expect(received.payloads.first.value, 'https://example.com');
      expect(received.suggestedPrompt, contains('https://example.com'));
      await controller.close();
      await cubit.close();
    });

    test('stream error emits ShareTargetError', () async {
      final controller = StreamController<List<SharedPayload>>();
      when(() => service.payloadStream)
          .thenAnswer((_) => controller.stream);
      final cubit = buildCubit();
      await cubit.init();

      controller.addError(Exception('share failed'));
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(cubit.state, isA<ShareTargetError>());
      await controller.close();
      await cubit.close();
    });

    blocTest<ShareTargetCubit, ShareTargetState>(
      'init emits Error when startListening throws',
      build: () {
        when(() => service.startListening())
            .thenThrow(Exception('platform unavailable'));
        return buildCubit();
      },
      act: (cubit) => cubit.init(),
      expect: () => [
        isA<ShareTargetListening>(),
        isA<ShareTargetError>(),
      ],
    );

    test('consume returns payloads and returns to Listening', () async {
      when(() => service.getInitialPayloads())
          .thenAnswer((_) async => [textPayload, urlPayload]);
      final cubit = buildCubit();
      await cubit.init();
      expect(cubit.state, isA<ShareTargetReceived>());

      final consumed = cubit.consume();

      expect(consumed, hasLength(2));
      expect(cubit.state, isA<ShareTargetListening>());
      verify(() => service.reset()).called(1);
      await cubit.close();
    });

    test('consume returns empty list when nothing pending', () async {
      final cubit = buildCubit();
      await cubit.init();
      expect(cubit.consume(), isEmpty);
      await cubit.close();
    });

    blocTest<ShareTargetCubit, ShareTargetState>(
      'clearPayloads discards payloads and emits Listening',
      build: () {
        when(() => service.getInitialPayloads())
            .thenAnswer((_) async => [textPayload]);
        return buildCubit();
      },
      act: (cubit) async {
        await cubit.init();
        await cubit.clearPayloads();
      },
      expect: () => [
        isA<ShareTargetListening>(),
        isA<ShareTargetReceived>(),
        isA<ShareTargetListening>(),
      ],
      verify: (_) => verify(() => service.reset()).called(1),
    );
  });
}
