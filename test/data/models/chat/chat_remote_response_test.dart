import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/data/models/chat/chat_remote_response.dart';

void main() {
  group('ToolCallDeltaRemoteResponse', () {
    test('fromJson parses a complete tool call delta', () {
      final json = <String, dynamic>{
        'index': 0,
        'id': 'call_abc123',
        'function': {
          'name': 'get_weather',
          'arguments': '{"city":"',
        },
      };

      final delta = ToolCallDeltaRemoteResponse.fromJson(json);

      expect(delta.index, 0);
      expect(delta.id, 'call_abc123');
      expect(delta.name, 'get_weather');
      expect(delta.argumentsFragment, '{"city":"');
    });

    test('toJson serializes correctly', () {
      final delta = ToolCallDeltaRemoteResponse(
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

    test('toDomain maps to ToolCallDelta', () {
      final delta = ToolCallDeltaRemoteResponse(
        index: 0,
        id: 'call_1',
        name: 'test_tool',
        argumentsFragment: '{}',
      );
      final domain = delta.toDomain();
      expect(domain.index, 0);
      expect(domain.id, 'call_1');
      expect(domain.name, 'test_tool');
      expect(domain.argumentsFragment, '{}');
    });
  });

  group('ToolCallResultRemoteResponse', () {
    test('fromJson parses tool call result', () {
      final json = <String, dynamic>{
        'tool_call_id': 'call_123',
        'name': 'get_weather',
        'content': '{"temp": 20}',
      };

      final result = ToolCallResultRemoteResponse.fromJson(json);

      expect(result.toolCallId, 'call_123');
      expect(result.name, 'get_weather');
      expect(result.content, '{"temp": 20}');
    });

    test('toJson produces the correct map', () {
      final result = ToolCallResultRemoteResponse(
        toolCallId: 'call_123',
        name: 'get_weather',
        content: '{"temp": 20}',
      );

      expect(result.toJson(), {
        'role': 'tool',
        'tool_call_id': 'call_123',
        'name': 'get_weather',
        'content': '{"temp": 20}',
      });
    });

    test('toDomain maps to ToolCallResult', () {
      final result = ToolCallResultRemoteResponse(
        toolCallId: 'call_123',
        name: 'get_weather',
        content: '{"temp": 20}',
      );
      final domain = result.toDomain();
      expect(domain.toolCallId, 'call_123');
      expect(domain.name, 'get_weather');
      expect(domain.content, '{"temp": 20}');
    });
  });

  group('ChatMessageRemoteResponse', () {
    test('fromJson parses assistant message with content', () {
      final json = <String, dynamic>{
        'role': 'assistant',
        'content': 'Hello!',
      };

      final msg = ChatMessageRemoteResponse.fromJson(json);

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

      final msg = ChatMessageRemoteResponse.fromJson(json);

      expect(msg.role, 'assistant');
      expect(msg.content, isNull);
      expect(msg.toolCalls, hasLength(1));
      expect(msg.toolCalls!.first.name, 'search');
    });

    test('toJson produces correct user message map', () {
      final msg = ChatMessageRemoteResponse(role: 'user', content: 'Hello');
      expect(msg.toJson(), {'role': 'user', 'content': 'Hello'});
    });

    test('toJson produces correct tool message map', () {
      final msg = ChatMessageRemoteResponse(
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

    test('toDomain maps to ChatMessage', () {
      final msg = ChatMessageRemoteResponse(
        role: 'user',
        content: 'Hello',
      );
      final domain = msg.toDomain();
      expect(domain.role, 'user');
      expect(domain.content, 'Hello');
    });
  });

  group('ChatChunkRemoteResponse', () {
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

      final chunk = ChatChunkRemoteResponse.fromJson(json);

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

      final chunk = ChatChunkRemoteResponse.fromJson(json);

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

      final chunk = ChatChunkRemoteResponse.fromJson(json);

      expect(chunk.finishReason, 'stop');
      expect(chunk.contentDelta, isNull);
    });

    test('fromJson handles empty choices', () {
      final json = <String, dynamic>{
        'id': 'chatcmpl-000',
        'model': 'gpt-4',
        'choices': <dynamic>[],
      };

      final chunk = ChatChunkRemoteResponse.fromJson(json);

      expect(chunk.id, 'chatcmpl-000');
      expect(chunk.contentDelta, isNull);
      expect(chunk.finishReason, isNull);
    });

    test('toDomain maps to ChatChunk', () {
      final chunk = ChatChunkRemoteResponse(
        id: 'chatcmpl-123',
        model: 'gpt-4',
        contentDelta: 'Hello',
      );
      final domain = chunk.toDomain();
      expect(domain.id, 'chatcmpl-123');
      expect(domain.model, 'gpt-4');
      expect(domain.contentDelta, 'Hello');
    });
  });
}
