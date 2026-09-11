import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/features/chat/data/models/chat_models.dart';

void main() {
  group('ToolCallDelta', () {
    test('fromJson parses a complete tool call delta', () {
      final json = <String, dynamic>{
        'index': 0,
        'id': 'call_abc123',
        'function': {
          'name': 'get_weather',
          'arguments': '{"city":"',
        },
      };

      final delta = ToolCallDelta.fromJson(json);

      expect(delta.index, 0);
      expect(delta.id, 'call_abc123');
      expect(delta.name, 'get_weather');
      expect(delta.argumentsFragment, '{"city":"');
    });

    test('fromJson parses a delta with only argument fragment', () {
      final json = <String, dynamic>{
        'index': 0,
        'function': {
          'arguments': 'Tokyo"}',
        },
      };

      final delta = ToolCallDelta.fromJson(json);

      expect(delta.index, 0);
      expect(delta.id, isNull);
      expect(delta.name, isNull);
      expect(delta.argumentsFragment, 'Tokyo"}');
    });

    test('fromJson defaults argumentsFragment to empty string', () {
      final json = <String, dynamic>{
        'index': 0,
      };

      final delta = ToolCallDelta.fromJson(json);

      expect(delta.argumentsFragment, '');
    });

    test('toJson serializes correctly', () {
      const delta = ToolCallDelta(
        index: 0,
        id: 'call_1',
        name: 'test_tool',
        argumentsFragment: '{}',
      );
      final json = delta.toJson();
      expect(json['index'], 0);
      expect(json['id'], 'call_1');
      expect(json['function']['name'], 'test_tool');
      expect(json['function']['arguments'], '{}');
    });

    test('equality works with same values', () {
      const a = ToolCallDelta(index: 0, id: 'x', name: 'fn');
      const b = ToolCallDelta(index: 0, id: 'x', name: 'fn');

      expect(a, equals(b));
    });
  });

  group('ToolCallResult', () {
    test('toJson produces the correct map', () {
      const result = ToolCallResult(
        toolCallId: 'call_123',
        name: 'get_weather',
        content: '{"temp": 20}',
      );

      final json = result.toJson();

      expect(json, {
        'role': 'tool',
        'tool_call_id': 'call_123',
        'name': 'get_weather',
        'content': '{"temp": 20}',
      });
    });

    test('equality works with same values', () {
      const a = ToolCallResult(
          toolCallId: 'id', name: 'fn', content: 'c');
      const b = ToolCallResult(
          toolCallId: 'id', name: 'fn', content: 'c');

      expect(a, equals(b));
    });
  });

  group('ChatMessage', () {
    test('fromJson parses assistant message with content', () {
      final json = <String, dynamic>{
        'role': 'assistant',
        'content': 'Hello!',
      };

      final msg = ChatMessage.fromJson(json);

      expect(msg.role, 'assistant');
      expect(msg.content, 'Hello!');
      expect(msg.toolCalls, isNull);
    });

    test('fromJson parses message with tool_calls', () {
      final json = <String, dynamic>{
        'role': 'assistant',
        'content': null,
        'tool_calls': [
          {
            'index': 0,
            'id': 'call_1',
            'function': {
              'name': 'search',
              'arguments': '{"q":"dart"}',
            },
          },
        ],
      };

      final msg = ChatMessage.fromJson(json);

      expect(msg.role, 'assistant');
      expect(msg.content, isNull);
      expect(msg.toolCalls, hasLength(1));
      expect(msg.toolCalls!.first.name, 'search');
    });

    test('toJson produces correct user message map', () {
      const msg = ChatMessage(role: 'user', content: 'Hello');
      expect(msg.toJson(), {'role': 'user', 'content': 'Hello'});
    });

    test('toJson produces correct tool message map', () {
      const msg = ChatMessage(
        role: 'tool',
        toolCallId: 'call_1',
        name: 'device_status',
        content: '{"battery": 80}',
      );
      expect(msg.toJson(), {
        'role': 'tool',
        'content': '{"battery": 80}',
        'tool_call_id': 'call_1',
        'name': 'device_status',
      });
    });

    test('toJson produces correct assistant with tool_calls map', () {
      const msg = ChatMessage(
        role: 'assistant',
        content: null,
        toolCalls: [
          ToolCallDelta(
            index: 0,
            id: 'call_1',
            name: 'get_battery',
            argumentsFragment: '{}',
          ),
        ],
      );
      final json = msg.toJson();
      expect(json['role'], 'assistant');
      expect(json['tool_calls'], isA<List>());
      final tc = (json['tool_calls'] as List).first as Map<String, dynamic>;
      expect(tc['id'], 'call_1');
      expect(tc['type'], 'function');
      expect(tc['function']['name'], 'get_battery');
    });

    test('copyWith copies and overrides fields correctly', () {
      const msg = ChatMessage(role: 'user', content: 'Original');
      final updated = msg.copyWith(content: 'Updated');
      expect(updated.role, 'user');
      expect(updated.content, 'Updated');

      final withRole = msg.copyWith(role: 'assistant');
      expect(withRole.role, 'assistant');
      expect(withRole.content, 'Original');
    });
  });

  group('ChatChunk', () {
    test('fromJson parses a content delta chunk', () {
      final json = <String, dynamic>{
        'id': 'chatcmpl-123',
        'model': 'gpt-4',
        'choices': [
          {
            'delta': {
              'content': 'Hello',
            },
            'finish_reason': null,
          },
        ],
      };

      final chunk = ChatChunk.fromJson(json);

      expect(chunk.id, 'chatcmpl-123');
      expect(chunk.model, 'gpt-4');
      expect(chunk.contentDelta, 'Hello');
      expect(chunk.toolCallDeltas, isNull);
      expect(chunk.finishReason, isNull);
    });

    test('fromJson parses a tool_calls delta chunk', () {
      final json = <String, dynamic>{
        'id': 'chatcmpl-456',
        'model': 'gpt-4',
        'choices': [
          {
            'delta': {
              'tool_calls': [
                {
                  'index': 0,
                  'id': 'call_abc',
                  'function': {
                    'name': 'get_weather',
                    'arguments': '{"city":',
                  },
                },
              ],
            },
            'finish_reason': null,
          },
        ],
      };

      final chunk = ChatChunk.fromJson(json);

      expect(chunk.toolCallDeltas, hasLength(1));
      expect(chunk.toolCallDeltas!.first.name, 'get_weather');
      expect(chunk.toolCallDeltas!.first.argumentsFragment, '{"city":');
    });

    test('fromJson parses finish_reason stop', () {
      final json = <String, dynamic>{
        'id': 'chatcmpl-789',
        'model': 'gpt-4',
        'choices': [
          {
            'delta': <String, dynamic>{},
            'finish_reason': 'stop',
          },
        ],
      };

      final chunk = ChatChunk.fromJson(json);

      expect(chunk.finishReason, 'stop');
      expect(chunk.contentDelta, isNull);
    });

    test('fromJson handles empty choices', () {
      final json = <String, dynamic>{
        'id': 'chatcmpl-000',
        'model': 'gpt-4',
        'choices': <dynamic>[],
      };

      final chunk = ChatChunk.fromJson(json);

      expect(chunk.id, 'chatcmpl-000');
      expect(chunk.contentDelta, isNull);
      expect(chunk.finishReason, isNull);
    });

    test('fromJson handles no choices key', () {
      final json = <String, dynamic>{
        'id': 'chatcmpl-noc',
        'model': 'gpt-4',
      };

      final chunk = ChatChunk.fromJson(json);

      expect(chunk.id, 'chatcmpl-noc');
      expect(chunk.contentDelta, isNull);
    });

    test('fromJson parses tool_calls finish_reason', () {
      final json = <String, dynamic>{
        'id': 'chatcmpl-tc',
        'model': 'gpt-4',
        'choices': [
          {
            'delta': <String, dynamic>{},
            'finish_reason': 'tool_calls',
          },
        ],
      };

      final chunk = ChatChunk.fromJson(json);

      expect(chunk.finishReason, 'tool_calls');
    });
  });
}
