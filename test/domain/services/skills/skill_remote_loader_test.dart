import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/remote/skills/skill_remote_loader.dart';
import 'package:flutter_ai_agent/domain/services/skills/skill_remote_loader.dart';

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

    test('rejects loopback and local hosts', () {
      for (final url in [
        'http://localhost/',
        'https://localhost/x',
        'https://evil.local/x',
      ]) {
        final reason = SkillRemoteLoaderBase.validateSourceUrl(url);
        expect(reason, isNotNull, reason: url);
      }
    });

    test('rejects private and link-local ipv4 hosts', () {
      for (final url in [
        'https://127.0.0.1/x',
        'https://10.0.0.1/x',
        'https://172.16.5.5/x',
        'https://192.168.1.1/x',
        'https://169.254.169.254/latest/meta-data/',
        'https://0.0.0.0/x',
      ]) {
        final reason = SkillRemoteLoaderBase.validateSourceUrl(url);
        expect(
          reason,
          'URL host is not allowed: ${Uri.parse(url).host}',
          reason: url,
        );
      }
    });

    test('rejects ipv6 loopback', () {
      final reason = SkillRemoteLoaderBase.validateSourceUrl('https://[::1]/x');
      expect(reason, isNotNull);
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

    test('private host url returns ParseFailure without throwing', () async {
      final loader = SkillRemoteLoader(dio: Dio());
      final result = await loader.fetchSkillMarkdown(
        'https://169.254.169.254/latest/meta-data/',
      );
      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => throw StateError('x'));
      expect(failure, isA<ParseFailure>());
    });
  });
}
