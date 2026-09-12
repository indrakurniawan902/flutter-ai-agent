import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/data/datasources/remote/chat/sse_parser.dart';

void main() {
  late SseParser parser;

  setUp(() {
    parser = SseParser();
  });

  group('SseParser.parse', () {
    test('parses a single SSE data line with content delta', () {
      const line =
          'data: {"id":"chatcmpl-1","model":"gpt-4","choices":[{"delta":{"content":"Hi"},"finish_reason":null}]}';

      final chunks = parser.parse(line);

      expect(chunks, hasLength(1));
      expect(chunks.first.contentDelta, 'Hi');
      expect(chunks.first.id, 'chatcmpl-1');
    });

    test('parses multi-line SSE block with multiple data lines', () {
      const block = '''data: {"id":"c1","model":"gpt-4","choices":[{"delta":{"content":"Hello"},"finish_reason":null}]}
data: {"id":"c2","model":"gpt-4","choices":[{"delta":{"content":" world"},"finish_reason":null}]}''';

      final chunks = parser.parse(block);

      expect(chunks, hasLength(2));
      expect(chunks[0].contentDelta, 'Hello');
      expect(chunks[1].contentDelta, ' world');
    });

    test('skips empty lines', () {
      const block = '''
data: {"id":"c1","model":"gpt-4","choices":[{"delta":{"content":"A"},"finish_reason":null}]}

data: {"id":"c2","model":"gpt-4","choices":[{"delta":{"content":"B"},"finish_reason":null}]}
''';

      final chunks = parser.parse(block);

      expect(chunks, hasLength(2));
    });

    test('skips SSE comment lines starting with colon', () {
      const block = ''': this is a comment
data: {"id":"c1","model":"gpt-4","choices":[{"delta":{"content":"ok"},"finish_reason":null}]}''';

      final chunks = parser.parse(block);

      expect(chunks, hasLength(1));
      expect(chunks.first.contentDelta, 'ok');
    });

    test('skips [DONE] signal', () {
      const block = '''data: {"id":"c1","model":"gpt-4","choices":[{"delta":{"content":"end"},"finish_reason":"stop"}]}
data: [DONE]''';

      final chunks = parser.parse(block);

      expect(chunks, hasLength(1));
      expect(chunks.first.finishReason, 'stop');
    });

    test('returns empty list for only [DONE]', () {
      const line = 'data: [DONE]';

      final chunks = parser.parse(line);

      expect(chunks, isEmpty);
    });

    test('skips malformed JSON lines', () {
      const block = '''data: {"id":"c1","model":"gpt-4","choices":[{"delta":{"content":"ok"},"finish_reason":null}]}
data: {malformed json here
data: {"id":"c2","model":"gpt-4","choices":[{"delta":{"content":"!"},"finish_reason":null}]}''';

      final chunks = parser.parse(block);

      expect(chunks, hasLength(2));
      expect(chunks[0].contentDelta, 'ok');
      expect(chunks[1].contentDelta, '!');
    });

    test('parses tool_calls deltas in SSE stream', () {
      const line =
          'data: {"id":"tc1","model":"gpt-4","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_xyz","function":{"name":"search","arguments":"{\\"q\\":\\""}}]},"finish_reason":null}]}';

      final chunks = parser.parse(line);

      expect(chunks, hasLength(1));
      expect(chunks.first.toolCallDeltas, hasLength(1));
      expect(chunks.first.toolCallDeltas!.first.name, 'search');
      expect(chunks.first.toolCallDeltas!.first.id, 'call_xyz');
    });

    test('handles multi-line SSE with mixed content and tool deltas', () {
      const block =
          'data: {"id":"m1","model":"gpt-4","choices":[{"delta":{"content":"thinking..."},"finish_reason":null}]}\n'
          'data: {"id":"m2","model":"gpt-4","choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","function":{"name":"calc","arguments":"{\\"x\\":"}}]},"finish_reason":null}]}\n'
          'data: {"id":"m3","model":"gpt-4","choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":"1}"}}]},"finish_reason":null}]}\n'
          'data: {"id":"m4","model":"gpt-4","choices":[{"delta":{},"finish_reason":"tool_calls"}]}\n'
          'data: [DONE]';

      final chunks = parser.parse(block);

      expect(chunks, hasLength(4));
      expect(chunks[0].contentDelta, 'thinking...');
      expect(chunks[1].toolCallDeltas!.first.name, 'calc');
      expect(chunks[2].toolCallDeltas!.first.argumentsFragment, '1}');
      expect(chunks[3].finishReason, 'tool_calls');
    });

    test('skips non-data lines without data: prefix', () {
      const block = '''event: message
data: {"id":"c1","model":"gpt-4","choices":[{"delta":{"content":"hi"},"finish_reason":null}]}
id: 123''';

      final chunks = parser.parse(block);

      expect(chunks, hasLength(1));
      expect(chunks.first.contentDelta, 'hi');
    });
  });

  group('SseParser.isDone', () {
    test('returns true for [DONE] line', () {
      expect(parser.isDone('data: [DONE]'), isTrue);
    });

    test('returns true for [DONE] with extra whitespace', () {
      expect(parser.isDone('  data: [DONE]  '), isTrue);
    });

    test('returns false for data line', () {
      expect(parser.isDone('data: {"id":"x"}'), isFalse);
    });

    test('returns false for empty line', () {
      expect(parser.isDone(''), isFalse);
    });
  });
}
