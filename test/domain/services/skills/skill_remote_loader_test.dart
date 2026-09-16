import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/remote/skills/skill_remote_loader.dart';
import 'package:flutter_ai_agent/domain/services/skills/skill_remote_loader.dart';

class _RedirectAdapter implements HttpClientAdapter {
  _RedirectAdapter(this.handler);

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

void main() {
  group('validateSourceUrl', () {
    test('accepts a raw github https url', () {
      expect(
        SkillRemoteLoaderBase.validateSourceUrl(
          'https://raw.githubusercontent.com/o/r/main/SKILL.md',
        ),
        isNull,
      );
    });

    test('rejects empty and non-url input', () {
      expect(SkillRemoteLoaderBase.validateSourceUrl(''), isNotNull);
      expect(SkillRemoteLoaderBase.validateSourceUrl('   '), isNotNull);
      expect(SkillRemoteLoaderBase.validateSourceUrl('not a url'), isNotNull);
    });

    test('rejects non https schemes', () {
      expect(
        SkillRemoteLoaderBase.validateSourceUrl('ftp://x'),
        'Unsupported URL scheme: ftp',
      );
      expect(
        SkillRemoteLoaderBase.validateSourceUrl('http://example.com/SKILL.md'),
        'Unsupported URL scheme: http',
      );
    });

    test('accepts digit-leading public hosts', () {
      expect(
        SkillRemoteLoaderBase.validateSourceUrl('https://10.example.com/x'),
        isNull,
      );
      expect(
        SkillRemoteLoaderBase.validateSourceUrl('https://1password.com/x'),
        isNull,
      );
    });
  });

  group('SkillRemoteLoader pre-network paths', () {
    test('invalid url returns ParseFailure without throwing', () async {
      final loader = SkillRemoteLoader(dio: Dio());
      final result = await loader.fetchSkillMarkdown('not a url');
      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => throw StateError('x'));
      expect(failure, isA<ParseFailure>());
    });

    test('http url returns ParseFailure without throwing', () async {
      final loader = SkillRemoteLoader(dio: Dio());
      final result = await loader.fetchSkillMarkdown(
        'http://example.com/SKILL.md',
      );
      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => throw StateError('x'));
      expect(failure, isA<ParseFailure>());
      expect(failure.message, 'Unsupported URL scheme: http');
    });
  });

  group('SkillRemoteLoader redirects', () {
    test('302 to a different host is refused', () async {
      final adapter = _RedirectAdapter(
        (_) => ResponseBody(
          Stream.value(Uint8List(0)),
          302,
          headers: {
            'location': ['https://other.example.org/SKILL.md'],
          },
        ),
      );
      final loader = SkillRemoteLoader(dio: Dio()..httpClientAdapter = adapter);

      final result = await loader.fetchSkillMarkdown(
        'https://example.com/SKILL.md',
      );

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => throw StateError('x'));
      expect(failure, isA<NetworkFailure>());
      expect(failure.message, 'Redirected to a different host');
      expect(adapter.requests.length, 1);
    });
  });
}
