import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/remote/skills/skill_remote_loader.dart';
import 'package:flutter_ai_agent/domain/services/skills/skill_remote_loader.dart';

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.handler);

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

Dio _dioWith(_FakeAdapter adapter) {
  return Dio()..httpClientAdapter = adapter;
}

void main() {
  group('validateSourceUrl rejects every canonical private form', () {
    test('ipv6 loopback, mapped, 6to4, and NAT64 forms', () {
      for (final url in [
        'https://[0:0:0:0:0:0:0:1]/',
        'https://[::ffff:127.0.0.1]/',
        'https://[::ffff:7f00:1]/',
        'https://[::ffff:169.254.169.254]/latest/meta-data/',
        'https://[2002:7f00:1::]/',
        'https://[64:ff9b::7f00:1]/',
      ]) {
        expect(
          SkillRemoteLoaderBase.validateSourceUrl(url),
          isNotNull,
          reason: url,
        );
      }
    });

    test('trailing-dot hosts', () {
      for (final url in [
        'https://127.0.0.1./',
        'https://localhost./',
        'https://10.0.0.1./',
        'https://169.254.169.254./',
      ]) {
        expect(
          SkillRemoteLoaderBase.validateSourceUrl(url),
          isNotNull,
          reason: url,
        );
      }
    });

    test('wildcard-DNS names embedding a private address', () {
      expect(
        SkillRemoteLoaderBase.validateSourceUrl('https://127.0.0.1.nip.io/x'),
        isNotNull,
      );
    });

    test('canonicaliseHost lowercases and strips trailing dots', () {
      expect(SkillRemoteLoaderBase.canonicaliseHost('LOCALHOST.'), 'localhost');
      expect(SkillRemoteLoaderBase.canonicaliseHost('[::1]'), '[::1]');
      expect(
        SkillRemoteLoaderBase.canonicaliseHost('127.0.0.1...'),
        '127.0.0.1',
      );
    });

    test('guard: public hosts are still accepted', () {
      for (final url in [
        'https://raw.githubusercontent.com/o/r/main/SKILL.md',
        'https://10.example.com/x',
        'https://1password.com/x',
        'https://[2606:4700::1111]/x',
      ]) {
        expect(
          SkillRemoteLoaderBase.validateSourceUrl(url),
          isNull,
          reason: url,
        );
      }
    });
  });

  group('SkillRemoteLoader manual redirect handling', () {
    test(
      'redirect to a disallowed host fails before the next request',
      () async {
        final adapter = _FakeAdapter(
          (_) => ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['https://127.0.0.1./evil.md'],
            },
          ),
        );
        final loader = SkillRemoteLoader(dio: _dioWith(adapter));

        final result = await loader.fetchSkillMarkdown(
          'https://example.com/SKILL.md',
        );

        expect(result.isLeft(), isTrue);
        final failure = result.fold((l) => l, (_) => throw StateError('x'));
        expect(failure, isA<NetworkFailure>());
        expect(failure.message, 'Redirected to a disallowed host');
        expect(adapter.requests, hasLength(1));
      },
    );

    test('redirect to an allowed host is followed and succeeds', () async {
      final adapter = _FakeAdapter((options) {
        if (options.uri.toString() == 'https://example.com/SKILL.md') {
          return ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['/moved/SKILL.md'],
            },
          );
        }
        return ResponseBody.fromString('---\nname: x\n---\n', 200);
      });
      final loader = SkillRemoteLoader(dio: _dioWith(adapter));

      final result = await loader.fetchSkillMarkdown(
        'https://example.com/SKILL.md',
      );

      expect(result.isRight(), isTrue);
      expect(adapter.requests, [
        'https://example.com/SKILL.md',
        'https://example.com/moved/SKILL.md',
      ]);
    });

    test('redirect without a location header fails closed', () async {
      final adapter = _FakeAdapter((_) => ResponseBody.fromString('', 302));
      final loader = SkillRemoteLoader(dio: _dioWith(adapter));

      final result = await loader.fetchSkillMarkdown(
        'https://example.com/SKILL.md',
      );

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => throw StateError('x'));
      expect(failure, isA<NetworkFailure>());
      expect(failure.message, 'Redirected without a location header');
    });

    test('redirect loop is capped at three hops', () async {
      final adapter = _FakeAdapter(
        (_) => ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['https://example.com/loop.md'],
          },
        ),
      );
      final loader = SkillRemoteLoader(dio: _dioWith(adapter));

      final result = await loader.fetchSkillMarkdown(
        'https://example.com/SKILL.md',
      );

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => throw StateError('x'));
      expect(failure.message, 'Too many redirects');
      expect(adapter.requests, hasLength(4));
    });
  });

  group('SkillRemoteLoader declared size cap', () {
    test('oversized content-length is refused before buffering', () async {
      final adapter = _FakeAdapter(
        (_) => ResponseBody.fromString(
          'tiny',
          200,
          headers: {
            'content-length': ['${SkillRemoteLoader.maxDocumentBytes + 1}'],
          },
        ),
      );
      final loader = SkillRemoteLoader(dio: _dioWith(adapter));

      final result = await loader.fetchSkillMarkdown(
        'https://example.com/SKILL.md',
      );

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => throw StateError('x'));
      expect(failure, isA<NetworkFailure>());
      expect(failure.message, 'Skill document too large (max 256 KB)');
    });

    test('body over the cap is still refused after download', () async {
      final oversized = 'a' * (SkillRemoteLoader.maxDocumentBytes + 1);
      final adapter = _FakeAdapter(
        (_) => ResponseBody.fromString(oversized, 200),
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
  });
}
