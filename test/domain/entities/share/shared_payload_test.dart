import 'package:flutter_ai_agent/domain/entities/share/shared_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildLinkContextBlock', () {
    test('happy path formats title and body', () {
      expect(
        SharedPayload.buildLinkContextBlock(
          url: 'https://a.test',
          title: 'Title',
          text: 'body',
        ),
        '[LINK CONTEXT] Title :: body',
      );
    });

    test('failure fallback keeps marker and raw url', () {
      final block = SharedPayload.buildLinkContextBlock(
        url: 'https://a.test/x',
        title: '',
        text: '',
      );
      expect(block, contains('(unavailable — '));
      expect(block, contains('https://a.test/x'));
    });
  });

  group('toPromptWithLinkContext', () {
    test('contains prefix and body', () {
      const payload = SharedPayload(
        kind: SharedPayloadKind.url,
        value: 'https://a.test',
      );
      final prompt = payload.toPromptWithLinkContext(
        url: 'https://a.test',
        title: 'Title',
        text: 'the article body',
      );
      expect(prompt, contains(SharedPayload.linkContextPrefix));
      expect(prompt, contains('the article body'));
    });
  });

  group('buildSuggestedPrompt', () {
    test('unchanged for text payload (no url data)', () {
      const payload = SharedPayload(
        kind: SharedPayloadKind.text,
        value: 'hello',
      );
      expect(
        SharedPayload.buildSuggestedPrompt([payload]),
        'Process this shared text:\n\nhello',
      );
    });
  });
}
