import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/remote/skills/skill_remote_loader.dart';

class _SizeCapAdapter implements HttpClientAdapter {
  _SizeCapAdapter(this.handler);

  final ResponseBody Function(RequestOptions options) handler;
  final List<String> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options.uri.toString());
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(_SizeCapAdapter adapter) {
  return Dio()..httpClientAdapter = adapter;
}

Stream<Uint8List> _oversizedChunks() async* {
  final chunk = Uint8List(64 * 1024);
  for (var i = 0; i < 5; i++) {
    yield Uint8List.fromList(chunk);
  }
}

void main() {
  final stalledControllers = <StreamController<Uint8List>>[];

  tearDown(() {
    for (final controller in stalledControllers) {
      controller.close();
    }
    stalledControllers.clear();
  });

  group('SkillRemoteLoader streamed size cap', () {
    test('declared oversized content-length is refused without '
        'consuming the body', () async {
      final stalled = StreamController<Uint8List>();
      stalledControllers.add(stalled);
      final adapter = _SizeCapAdapter(
        (_) => ResponseBody(
          stalled.stream,
          200,
          headers: {
            'content-length': ['8388608'],
          },
        ),
      );
      final loader = SkillRemoteLoader(dio: _dioWith(adapter));

      final stopwatch = Stopwatch()..start();
      final result = await loader.fetchSkillMarkdown(
        'https://example.com/SKILL.md',
      );
      stopwatch.stop();

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => throw StateError('x'));
      expect(failure, isA<NetworkFailure>());
      expect(failure.message, 'Skill document too large (max 256 KB)');
      expect(
        stopwatch.elapsed,
        lessThan(const Duration(seconds: 5)),
        reason: 'a stalled body must not be awaited when the header refuses it',
      );
    });

    test('a lying small content-length is caught by the byte cap', () async {
      final adapter = _SizeCapAdapter(
        (_) => ResponseBody(
          _oversizedChunks(),
          200,
          headers: {
            'content-length': ['100'],
          },
        ),
      );
      final loader = SkillRemoteLoader(dio: _dioWith(adapter));

      final result = await loader.fetchSkillMarkdown(
        'https://example.com/SKILL.md',
      );

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => throw StateError('x'));
      expect(failure, isA<ParseFailure>());
      expect(failure.message, 'Skill document too large (max 256 KB)');
    });

    test('a missing content-length is caught by the byte cap', () async {
      final adapter = _SizeCapAdapter(
        (_) => ResponseBody(_oversizedChunks(), 200),
      );
      final loader = SkillRemoteLoader(dio: _dioWith(adapter));

      final result = await loader.fetchSkillMarkdown(
        'https://example.com/SKILL.md',
      );

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => throw StateError('x'));
      expect(failure, isA<ParseFailure>());
      expect(failure.message, 'Skill document too large (max 256 KB)');
    });

    test('a small document round-trips byte-for-byte', () async {
      const document =
          '---\nname: caf\u00e9\n---\nR\u00e9sum\u00e9 na\u00efve '
          'fa\u00e7ade\n';
      final bytes = utf8.encode(document);
      expect(bytes.length, greaterThan(document.length));
      final adapter = _SizeCapAdapter(
        (_) => ResponseBody(
          Stream.value(Uint8List.fromList(bytes)),
          200,
          headers: {
            'content-length': ['${bytes.length}'],
          },
        ),
      );
      final loader = SkillRemoteLoader(dio: _dioWith(adapter));

      final result = await loader.fetchSkillMarkdown(
        'https://example.com/SKILL.md',
      );

      expect(result.isRight(), isTrue);
      final value = result.fold((l) => throw StateError('x'), (r) => r);
      expect(value, document);
    });
  });
}
