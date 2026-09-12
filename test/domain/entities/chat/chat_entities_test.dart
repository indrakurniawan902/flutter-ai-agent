import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ToolCallDelta', () {
    test('fromJson defaults argumentsFragment to empty string', () {
      final delta1 = ToolCallDelta.fromJson(const {});
      expect(delta1.index, equals(0));
      expect(delta1.id, isNull);
      expect(delta1.name, isNull);
      expect(delta1.argumentsFragment, equals(''));

      final delta2 = ToolCallDelta.fromJson(const {
        'index': 2,
        'id': 'call_abc',
        'function': {
          'name': 'get_location',
        },
      });
      expect(delta2.index, equals(2));
      expect(delta2.id, equals('call_abc'));
      expect(delta2.name, equals('get_location'));
      expect(delta2.argumentsFragment, equals(''));
    });

    test('copyWith updates specified fields and retains others', () {
      const delta = ToolCallDelta(
        index: 0,
        id: 'call_1',
        name: 'search',
        argumentsFragment: '{"q": "flutter"}',
      );

      final copy = delta.copyWith(
        index: 1,
        argumentsFragment: '{"q": "dart"}',
      );

      expect(copy.index, equals(1));
      expect(copy.id, equals('call_1'));
      expect(copy.name, equals('search'));
      expect(copy.argumentsFragment, equals('{"q": "dart"}'));
    });

    test('supports value equality', () {
      const delta1 = ToolCallDelta(
        index: 0,
        id: 'call_1',
        name: 'search',
        argumentsFragment: '{"q": "flutter"}',
      );

      const delta2 = ToolCallDelta(
        index: 0,
        id: 'call_1',
        name: 'search',
        argumentsFragment: '{"q": "flutter"}',
      );

      const delta3 = ToolCallDelta(
        index: 0,
        id: 'call_2',
        name: 'search',
        argumentsFragment: '{"q": "flutter"}',
      );

      expect(delta1, equals(delta2));
      expect(delta1, isNot(equals(delta3)));
    });

    test('toJson serializes correctly', () {
      const delta = ToolCallDelta(
        index: 0,
        id: 'call_1',
        name: 'search',
        argumentsFragment: '{"q": "flutter"}',
      );

      expect(delta.toJson(), equals({
        'index': 0,
        'id': 'call_1',
        'function': {
          'name': 'search',
          'arguments': '{"q": "flutter"}',
        },
      }));
    });
  });

  group('ToolCallResult', () {
    test('supports value equality', () {
      const result1 = ToolCallResult(
        toolCallId: 'call_1',
        name: 'search',
        content: '{"status": "ok"}',
      );

      const result2 = ToolCallResult(
        toolCallId: 'call_1',
        name: 'search',
        content: '{"status": "ok"}',
      );

      const result3 = ToolCallResult(
        toolCallId: 'call_1',
        name: 'search',
        content: '{"status": "error"}',
      );

      expect(result1, equals(result2));
      expect(result1, isNot(equals(result3)));
    });

    test('toJson serializes correctly', () {
      const result = ToolCallResult(
        toolCallId: 'call_123',
        name: 'get_weather',
        content: 'sunny',
      );

      expect(result.toJson(), equals({
        'role': 'tool',
        'tool_call_id': 'call_123',
        'name': 'get_weather',
        'content': 'sunny',
      }));
    });
  });

  group('ChatMessage', () {
    test('defaults null for optional fields in constructor and fromJson', () {
      const msg = ChatMessage(role: 'user');
      expect(msg.content, isNull);
      expect(msg.toolCalls, isNull);
      expect(msg.toolCallId, isNull);
      expect(msg.name, isNull);
      expect(msg.thoughtProcess, isNull);
      expect(msg.actionSteps, isNull);
      expect(msg.confirmationCard, isNull);
      expect(msg.summaryCard, isNull);

      final fromJsonMsg = ChatMessage.fromJson(const {'role': 'user'});
      expect(fromJsonMsg.role, equals('user'));
      expect(fromJsonMsg.content, isNull);
      expect(fromJsonMsg.toolCalls, isNull);
      expect(fromJsonMsg.toolCallId, isNull);
      expect(fromJsonMsg.name, isNull);
      expect(fromJsonMsg.thoughtProcess, isNull);
    });

    test('fromJson parses snake_case thought_process', () {
      final msg = ChatMessage.fromJson(const {
        'role': 'assistant',
        'content': 'Hello',
        'thought_process': 'Analyzing user input...',
      });

      expect(msg.thoughtProcess, equals('Analyzing user input...'));
    });

    test('fromJson parses camelCase thoughtProcess fallback', () {
      final msg = ChatMessage.fromJson(const {
        'role': 'assistant',
        'content': 'Hello',
        'thoughtProcess': 'Fallback reasoning...',
      });

      expect(msg.thoughtProcess, equals('Fallback reasoning...'));
    });

    test('toJson serializes toolCalls correctly', () {
      const msg = ChatMessage(
        role: 'assistant',
        toolCalls: [
          ToolCallDelta(
            index: 0,
            id: 'call_1',
            name: 'get_weather',
            argumentsFragment: '{"city": "Jakarta"}',
          ),
        ],
      );

      final json = msg.toJson();
      expect(json['role'], equals('assistant'));
      expect(json['tool_calls'], equals([
        {
          'id': 'call_1',
          'type': 'function',
          'function': {
            'name': 'get_weather',
            'arguments': '{"city": "Jakarta"}',
          },
        },
      ]));
    });

    test('toJson includes thought_process for local persistence', () {
      const msg = ChatMessage(
        role: 'assistant',
        content: 'Sample content',
        thoughtProcess: 'Internal thoughts',
      );

      final json = msg.toJson();
      expect(json['thought_process'], equals('Internal thoughts'));
      expect(json.containsKey('thoughtProcess'), isFalse);
      expect(json['role'], equals('assistant'));
      expect(json['content'], equals('Sample content'));
    });

    test('copyWith works for thoughtProcess and other fields', () {
      const msg = ChatMessage(
        role: 'assistant',
        content: 'Original content',
        thoughtProcess: 'Original thought',
      );

      final copy = msg.copyWith(
        thoughtProcess: 'Updated thought',
        content: 'Updated content',
      );

      expect(copy.role, equals('assistant'));
      expect(copy.content, equals('Updated content'));
      expect(copy.thoughtProcess, equals('Updated thought'));
    });

    test('supports value equality including thoughtProcess', () {
      const msg1 = ChatMessage(
        role: 'assistant',
        content: 'Hi',
        thoughtProcess: 'Thinking...',
      );

      const msg2 = ChatMessage(
        role: 'assistant',
        content: 'Hi',
        thoughtProcess: 'Thinking...',
      );

      const msg3 = ChatMessage(
        role: 'assistant',
        content: 'Hi',
        thoughtProcess: 'Different thought',
      );

      expect(msg1, equals(msg2));
      expect(msg1, isNot(equals(msg3)));
    });
  });

  group('ChatChunk', () {
    test('fromJson handles no choices key', () {
      final chunk = ChatChunk.fromJson(const {
        'id': 'chunk_001',
        'model': 'hermes-3-llama-3.1-8b',
      });

      expect(chunk.id, equals('chunk_001'));
      expect(chunk.model, equals('hermes-3-llama-3.1-8b'));
      expect(chunk.contentDelta, isNull);
      expect(chunk.toolCallDeltas, isNull);
      expect(chunk.finishReason, isNull);
    });

    test('fromJson handles empty choices list', () {
      final chunk = ChatChunk.fromJson(const {
        'id': 'chunk_002',
        'model': 'hermes-3-llama-3.1-8b',
        'choices': [],
      });

      expect(chunk.id, equals('chunk_002'));
      expect(chunk.model, equals('hermes-3-llama-3.1-8b'));
      expect(chunk.contentDelta, isNull);
      expect(chunk.toolCallDeltas, isNull);
      expect(chunk.finishReason, isNull);
    });

    test('fromJson parses finishReason tool_calls and toolCallDeltas', () {
      final chunk = ChatChunk.fromJson(const {
        'id': 'chunk_003',
        'model': 'gpt-4',
        'choices': [
          {
            'finish_reason': 'tool_calls',
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_xyz',
                  'function': {
                    'name': 'calculator',
                    'arguments': '{"expr": "1+1"}',
                  },
                },
              ],
            },
          },
        ],
      });

      expect(chunk.id, equals('chunk_003'));
      expect(chunk.finishReason, equals('tool_calls'));
      expect(chunk.toolCallDeltas, isNotNull);
      expect(chunk.toolCallDeltas!.length, equals(1));
      expect(chunk.toolCallDeltas!.first.id, equals('call_xyz'));
      expect(chunk.toolCallDeltas!.first.name, equals('calculator'));
      expect(
        chunk.toolCallDeltas!.first.argumentsFragment,
        equals('{"expr": "1+1"}'),
      );
    });

    test('supports value equality', () {
      const chunk1 = ChatChunk(
        id: 'c1',
        model: 'm1',
        contentDelta: 'hello',
        finishReason: 'stop',
      );

      const chunk2 = ChatChunk(
        id: 'c1',
        model: 'm1',
        contentDelta: 'hello',
        finishReason: 'stop',
      );

      const chunk3 = ChatChunk(
        id: 'c1',
        model: 'm1',
        contentDelta: 'world',
        finishReason: 'stop',
      );

      expect(chunk1, equals(chunk2));
      expect(chunk1, isNot(equals(chunk3)));
    });
  });
}
