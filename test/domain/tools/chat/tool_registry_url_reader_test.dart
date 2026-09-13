import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockUrlReaderService stub;
  late ToolRegistry registry;

  setUp(() {
    stub = MockUrlReaderService();
    registry = ToolRegistry(urlReaderService: stub);
  });

  group('read_web_page registration', () {
    test('tool present with tier2 and required url', () {
      expect(registry.hasTool('read_web_page'), isTrue);
      expect(registry.tools.map((t) => t.name), contains('read_web_page'));

      final tool = registry.getTool('read_web_page')!;
      expect(tool.securityTier, SecurityTier.tier2Permission);
      expect(tool.parameters['required'], ['url']);
    });

    test('absent when service not provided', () {
      expect(ToolRegistry().hasTool('read_web_page'), isFalse);
    });
  });

  group('read_web_page execution', () {
    test('executes stub and returns its Right payload', () async {
      when(() => stub.fetchReadableText('https://a.test'))
          .thenAnswer((_) async => const Right<Failure, String>('article body'));

      final result =
          await registry.executeTool('read_web_page', {'url': 'https://a.test'});

      expect(result, const Right<Failure, String>('article body'));
      verify(() => stub.fetchReadableText('https://a.test')).called(1);
    });

    test('propagates stub Left', () async {
      when(() => stub.fetchReadableText(any())).thenAnswer(
        (_) async => const Left<Failure, String>(ParseFailure('boom')),
      );

      final result =
          await registry.executeTool('read_web_page', {'url': 'https://a.test'});

      expect(result, isA<Left>());
      expect((result as Left).value, isA<ParseFailure>());
    });
  });
}
