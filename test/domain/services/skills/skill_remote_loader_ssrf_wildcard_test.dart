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
  group('validateSourceUrl refuses wildcard-DNS hyphen forms', () {
    test('hyphenated private and reserved IPv4 literals', () {
      for (final url in [
        'https://127-0-0-1.nip.io/SKILL.md',
        'https://127-0-0-1.sslip.io/SKILL.md',
        'https://10-0-0-1.sslip.io/SKILL.md',
        'https://192-168-1-1.sslip.io/SKILL.md',
        'https://100-64-0-1.sslip.io/SKILL.md',
        'https://198-18-0-1.sslip.io/SKILL.md',
      ]) {
        expect(
          SkillRemoteLoaderBase.validateSourceUrl(url),
          isNotNull,
          reason: url,
        );
      }
    });

    test('already-blocked canonical forms stay blocked', () {
      for (final url in [
        'https://127.0.0.1.nip.io/SKILL.md',
        'https://localhost./x',
        'https://[::1]/x',
        'https://[0:0:0:0:0:0:0:1]/x',
        'https://[::ffff:127.0.0.1]/x',
        'https://169.254.169.254/x',
        'https://10.0.0.1./x',
        'https://[fd00::1]/x',
        'https://[fe80::1]/x',
      ]) {
        expect(
          SkillRemoteLoaderBase.validateSourceUrl(url),
          isNotNull,
          reason: url,
        );
      }
    });
  });

  group('validateSourceUrl refuses mapped IPv6 variants', () {
    test('RFC 4291 2.2.3.1 shape with extra zero groups', () {
      for (final url in [
        'https://[::ffff:0:127.0.0.1]/SKILL.md',
        'https://[::ffff:0:7f00:1]/SKILL.md',
        'https://[::ffff:0:0:0:1]/SKILL.md',
        'https://[::ffff:0:169.254.169.254]/x',
        'https://[::FFFF:0:127.0.0.1]/x',
      ]) {
        expect(
          SkillRemoteLoaderBase.validateSourceUrl(url),
          isNotNull,
          reason: url,
        );
      }
    });

    test('6to4, NAT64, link-local, unique-local, loopback spellings', () {
      for (final url in [
        'https://[2002:7f00:1::]/x',
        'https://[64:ff9b::7f00:1]/x',
        'https://[FE80::1]/x',
        'https://[FE80::1%25eth0]/x',
        'https://[FD00::1]/x',
        'https://[::]/x',
      ]) {
        expect(
          SkillRemoteLoaderBase.validateSourceUrl(url),
          isNotNull,
          reason: url,
        );
      }
    });

    test('non-http(s) schemes stay refused', () {
      for (final url in ['ftp://x', 'file:///etc/passwd']) {
        expect(
          SkillRemoteLoaderBase.validateSourceUrl(url),
          isNotNull,
          reason: url,
        );
      }
    });
  });

  group('validateSourceUrl keeps public hosts allowed', () {
    test('documented allowlist plus public wildcard and mapped forms', () {
      for (final url in [
        'https://raw.githubusercontent.com/o/r/main/SKILL.md',
        'https://10.example.com/x',
        'https://1password.com/x',
        'https://[2606:4700::1111]/x',
        'https://[2001:db8:ffff::1]/x',
        'https://8-8-8-8.sslip.io/x',
        'https://[::ffff:8.8.8.8]/x',
        'https://[2002:808:808::]/x',
      ]) {
        expect(
          SkillRemoteLoaderBase.validateSourceUrl(url),
          isNull,
          reason: url,
        );
      }
    });
  });

  group('refused hosts never reach the network', () {
    test('hyphenated wildcard-DNS host fails before any request', () async {
      final adapter = _FakeAdapter(
        (_) => throw StateError('network must not be reached'),
      );
      final loader = SkillRemoteLoader(dio: _dioWith(adapter));

      final result = await loader.fetchSkillMarkdown(
        'https://127-0-0-1.nip.io/SKILL.md',
      );

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => throw StateError('x'));
      expect(failure, isA<ParseFailure>());
      expect(adapter.requests, isEmpty);
    });

    test('mapped IPv6 host fails before any request', () async {
      final adapter = _FakeAdapter(
        (_) => throw StateError('network must not be reached'),
      );
      final loader = SkillRemoteLoader(dio: _dioWith(adapter));

      final result = await loader.fetchSkillMarkdown(
        'https://[::ffff:0:127.0.0.1]/SKILL.md',
      );

      expect(result.isLeft(), isTrue);
      final failure = result.fold((l) => l, (_) => throw StateError('x'));
      expect(failure, isA<ParseFailure>());
      expect(adapter.requests, isEmpty);
    });
  });
}
