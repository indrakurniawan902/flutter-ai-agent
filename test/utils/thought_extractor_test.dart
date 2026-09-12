import 'package:flutter_ai_agent/utils/thought_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ThoughtExtractor', () {
    test('extracts single thought block', () {
      const raw =
          '<thought>Thinking step 1\nThinking step 2</thought>Here is the actual answer.';

      final result = ThoughtExtractor.extract(raw);

      expect(result.thoughtProcess, 'Thinking step 1\nThinking step 2');
      expect(result.cleanContent, 'Here is the actual answer.');
      expect(result.hasThought, isTrue);
    });

    test('concatenates multiple thought blocks with blank line', () {
      const raw =
          '<thought>Step A</thought>Middle text<thought>Step B</thought>End text';

      final result = ThoughtExtractor.extract(raw);

      expect(result.thoughtProcess, 'Step A\n\nStep B');
      expect(result.hasThought, isTrue);
      expect(result.cleanContent, contains('Middle text'));
      expect(result.cleanContent, contains('End text'));
      expect(result.cleanContent, isNot(contains('<thought>')));
    });

    test('handles text before, between, and after thought blocks', () {
      const raw =
          'Before <thought>Thought one</thought> Between <thought>Thought two</thought> After';

      final result = ThoughtExtractor.extract(raw);

      expect(result.thoughtProcess, 'Thought one\n\nThought two');
      expect(result.cleanContent, contains('Before'));
      expect(result.cleanContent, contains('Between'));
      expect(result.cleanContent, contains('After'));
      expect(result.cleanContent, isNot(contains('<thought>')));
    });

    test('returns null thought when no thought tags present', () {
      const raw = 'Just a plain answer with no tags.';

      final result = ThoughtExtractor.extract(raw);

      expect(result.thoughtProcess, isNull);
      expect(result.hasThought, isFalse);
      expect(result.cleanContent, 'Just a plain answer with no tags.');
    });

    test('handles empty string safely', () {
      final result = ThoughtExtractor.extract('');

      expect(result.thoughtProcess, isNull);
      expect(result.hasThought, isFalse);
      expect(result.cleanContent, isEmpty);
    });

    test('handles whitespace-only string safely', () {
      final result = ThoughtExtractor.extract('   \n  ');

      expect(result.thoughtProcess, isNull);
      expect(result.hasThought, isFalse);
      expect(result.cleanContent, isEmpty);
    });

    test('ignores unclosed tag when streaming is false', () {
      const raw = 'Answer start <thought>partial thinking without close';

      final result = ThoughtExtractor.extract(raw, streaming: false);

      expect(result.thoughtProcess, isNull);
      expect(result.hasThought, isFalse);
      expect(result.cleanContent, raw.trim());
    });

    test('extracts partial thought when streaming is true', () {
      const raw = 'Answer start <thought>partial thinking without close';

      final result = ThoughtExtractor.extract(raw, streaming: true);

      expect(result.thoughtProcess, 'partial thinking without close');
      expect(result.hasThought, isTrue);
      expect(result.cleanContent, 'Answer start');
    });

    test('tags are case sensitive', () {
      const raw = '<THOUGHT>foo</THOUGHT>Answer';

      final result = ThoughtExtractor.extract(raw);

      expect(result.thoughtProcess, isNull);
      expect(result.hasThought, isFalse);
      expect(result.cleanContent, raw.trim());
    });

    test('trims thought and clean content and collapses newlines', () {
      const raw = '<thought>  padded thought  </thought>Line1\n\n\n\nLine2';

      final result = ThoughtExtractor.extract(raw);

      expect(result.thoughtProcess, 'padded thought');
      expect(result.cleanContent, 'Line1\n\nLine2');
    });

    test('empty thought block yields null thoughtProcess', () {
      const raw = '<thought>   </thought>answer';

      final result = ThoughtExtractor.extract(raw);

      expect(result.thoughtProcess, isNull);
      expect(result.hasThought, isFalse);
      expect(result.cleanContent, 'answer');
    });
  });
}
