import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import 'package:flutter_ai_agent/domain/models/share/shared_payload.dart';
import 'package:flutter_ai_agent/domain/services/share/share_target_service.dart';

class MockShareMediaProvider extends Mock implements ShareMediaProvider {}

class MockSharedMediaFile extends Mock implements SharedMediaFile {}

SharedMediaFile mediaFile({
  required String path,
  required SharedMediaType type,
  String? mimeType,
  String? thumbnail,
  String? message,
}) {
  final file = MockSharedMediaFile();
  when(() => file.path).thenReturn(path);
  when(() => file.type).thenReturn(type);
  when(() => file.mimeType).thenReturn(mimeType);
  when(() => file.thumbnail).thenReturn(thumbnail);
  when(() => file.message).thenReturn(message);
  return file;
}

void main() {
  late MockShareMediaProvider provider;
  late ShareTargetService service;

  setUp(() {
    provider = MockShareMediaProvider();
    when(() => provider.getMediaStream())
        .thenAnswer((_) => const Stream.empty());
    when(() => provider.reset()).thenAnswer((_) async {});
    service = ShareTargetService(provider: provider);
  });

  tearDown(() async {
    await service.dispose();
  });

  group('SharedPayload prompt routing', () {
    test('routes text payload', () {
      const payload = SharedPayload(
        kind: SharedPayloadKind.text,
        value: 'hello world',
      );
      expect(payload.toChatPrompt(), contains('hello world'));
      expect(payload.toPrompt(), payload.toChatPrompt());
    });

    test('routes url payload', () {
      const payload = SharedPayload(
        kind: SharedPayloadKind.url,
        value: 'https://example.com',
      );
      expect(payload.toChatPrompt(), contains('https://example.com'));
    });

    test('routes image payload', () {
      const payload = SharedPayload(
        kind: SharedPayloadKind.image,
        value: '/tmp/a.png',
      );
      expect(payload.toChatPrompt(), contains('/tmp/a.png'));
    });

    test('routes video payload', () {
      const payload = SharedPayload(
        kind: SharedPayloadKind.video,
        value: '/tmp/a.mp4',
      );
      expect(payload.toChatPrompt(), contains('/tmp/a.mp4'));
    });

    test('routes file payload', () {
      const payload = SharedPayload(
        kind: SharedPayloadKind.file,
        value: '/tmp/a.pdf',
      );
      expect(payload.toChatPrompt(), contains('/tmp/a.pdf'));
    });

    test('buildSuggestedPrompt combines batches', () {
      final prompt = SharedPayload.buildSuggestedPrompt(const [
        SharedPayload(kind: SharedPayloadKind.text, value: 'a'),
        SharedPayload(kind: SharedPayloadKind.url, value: 'https://x.test'),
      ]);
      expect(prompt, contains('a'));
      expect(prompt, contains('https://x.test'));
    });

    test('buildSuggestedPrompt is empty for empty list', () {
      expect(SharedPayload.buildSuggestedPrompt(const []), isEmpty);
    });
  });

  group('ShareTargetService mapping', () {
    test('maps each SharedMediaType to payload kind', () {
      expect(
        service
            .mapFile(mediaFile(path: 'hi', type: SharedMediaType.text))?.kind,
        SharedPayloadKind.text,
      );
      expect(
        service
            .mapFile(
              mediaFile(
                path: 'https://example.com',
                type: SharedMediaType.url,
              ),
            )
            ?.kind,
        SharedPayloadKind.url,
      );
      expect(
        service
            .mapFile(mediaFile(path: '/a.png', type: SharedMediaType.image))
            ?.kind,
        SharedPayloadKind.image,
      );
      expect(
        service
            .mapFile(mediaFile(path: '/a.mp4', type: SharedMediaType.video))
            ?.kind,
        SharedPayloadKind.video,
      );
      expect(
        service
            .mapFile(mediaFile(path: '/a.pdf', type: SharedMediaType.file))
            ?.kind,
        SharedPayloadKind.file,
      );
    });

    test('mapFile preserves mimeType, thumbnail, and message', () {
      final payload = service.mapFile(mediaFile(
        path: '/a.png',
        type: SharedMediaType.image,
        mimeType: 'image/png',
        thumbnail: '/thumb.png',
        message: 'note',
      ));
      expect(payload?.mimeType, 'image/png');
      expect(payload?.thumbnail, '/thumb.png');
      expect(payload?.message, 'note');
    });

    test('mapFile returns null for blank path', () {
      expect(
        service.mapFile(mediaFile(path: '  ', type: SharedMediaType.text)),
        isNull,
      );
    });

    test('mapMediaFiles drops blank entries', () {
      final payloads = service.mapMediaFiles([
        mediaFile(path: '  ', type: SharedMediaType.text),
        mediaFile(path: 'hello', type: SharedMediaType.text),
      ]);
      expect(payloads, hasLength(1));
      expect(payloads.first.value, 'hello');
    });
  });

  group('ShareTargetService intake', () {
    test('getInitialPayloads returns mapped payloads and resets', () async {
      when(() => provider.getInitialMedia()).thenAnswer((_) async => [
            mediaFile(path: 'hello', type: SharedMediaType.text),
            mediaFile(
              path: 'https://example.com',
              type: SharedMediaType.url,
            ),
          ]);

      final payloads = await service.getInitialPayloads();

      expect(payloads, hasLength(2));
      expect(payloads[0].kind, SharedPayloadKind.text);
      expect(payloads[1].kind, SharedPayloadKind.url);
      verify(() => provider.reset()).called(1);
    });

    test('getInitialPayloads emits batch on payloadStream', () async {
      when(() => provider.getInitialMedia()).thenAnswer((_) async => [
            mediaFile(path: 'hello', type: SharedMediaType.text),
          ]);

      final future = expectLater(
        service.payloadStream,
        emits(predicate<List<SharedPayload>>(
          (p) => p.length == 1 && p.first.value == 'hello',
        )),
      );
      await service.getInitialPayloads();
      await future;
    });

    test('getInitialPayloads returns empty list when nothing shared',
        () async {
      when(() => provider.getInitialMedia()).thenAnswer((_) async => []);

      final payloads = await service.getInitialPayloads();

      expect(payloads, isEmpty);
      verify(() => provider.reset()).called(1);
    });

    test('startListening forwards live stream batches', () async {
      final controller = StreamController<List<SharedMediaFile>>();
      when(() => provider.getMediaStream())
          .thenAnswer((_) => controller.stream);

      await service.startListening();
      final future = expectLater(
        service.payloadStream,
        emits(predicate<List<SharedPayload>>(
          (p) => p.length == 1 && p.first.kind == SharedPayloadKind.image,
        )),
      );
      controller.add([mediaFile(path: '/a.png', type: SharedMediaType.image)]);
      await future;
      await controller.close();
    });

    test('startListening ignores empty batches', () async {
      final controller =
          StreamController<List<SharedMediaFile>>.broadcast();
      when(() => provider.getMediaStream())
          .thenAnswer((_) => controller.stream);

      await service.startListening();
      var emitted = false;
      final sub = service.payloadStream.listen((_) => emitted = true);
      controller.add([mediaFile(path: '   ', type: SharedMediaType.text)]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(emitted, isFalse);
      await sub.cancel();
      await controller.close();
    });

    test('reset delegates to provider', () async {
      await service.reset();
      verify(() => provider.reset()).called(1);
    });
  });
}
