import 'package:flutter_ai_agent/common/remote_response_mapper.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';

class ToolCallDeltaRemoteResponse implements ResponseMapper<ToolCallDelta> {
  final int index;
  final String? id;
  final String? name;
  final String argumentsFragment;

  ToolCallDeltaRemoteResponse({
    required this.index,
    this.id,
    this.name,
    this.argumentsFragment = '',
  });

  factory ToolCallDeltaRemoteResponse.fromJson(Map<String, dynamic> json) {
    final function_ = json['function'] as Map<String, dynamic>?;
    return ToolCallDeltaRemoteResponse(
      index: (json['index'] as int?) ?? 0,
      id: json['id'] as String?,
      name: function_?['name'] as String?,
      argumentsFragment: (function_?['arguments'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'index': index,
        if (id != null) 'id': id,
        'function': {
          if (name != null) 'name': name,
          'arguments': argumentsFragment,
        },
      };

  @override
  ToolCallDelta toDomain() => ToolCallDelta(
        index: index,
        id: id,
        name: name,
        argumentsFragment: argumentsFragment,
      );
}

class ToolCallResultRemoteResponse implements ResponseMapper<ToolCallResult> {
  final String toolCallId;
  final String name;
  final String content;

  ToolCallResultRemoteResponse({
    required this.toolCallId,
    required this.name,
    required this.content,
  });

  factory ToolCallResultRemoteResponse.fromJson(Map<String, dynamic> json) {
    return ToolCallResultRemoteResponse(
      toolCallId: json['tool_call_id'] as String,
      name: json['name'] as String,
      content: json['content'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'role': 'tool',
        'tool_call_id': toolCallId,
        'name': name,
        'content': content,
      };

  @override
  ToolCallResult toDomain() => ToolCallResult(
        toolCallId: toolCallId,
        name: name,
        content: content,
      );
}

class ChatMessageRemoteResponse implements ResponseMapper<ChatMessage> {
  final String role;
  final String? content;
  final List<ToolCallDeltaRemoteResponse>? toolCalls;
  final String? toolCallId;
  final String? name;
  final String? thoughtProcess;

  ChatMessageRemoteResponse({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolCallId,
    this.name,
    this.thoughtProcess,
  });

  factory ChatMessageRemoteResponse.fromJson(Map<String, dynamic> json) {
    final toolCallsList = json['tool_calls'] as List<dynamic>?;
    return ChatMessageRemoteResponse(
      role: json['role'] as String,
      content: json['content'] as String?,
      toolCalls: toolCallsList
          ?.map(
            (e) => ToolCallDeltaRemoteResponse.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      toolCallId: json['tool_call_id'] as String?,
      name: json['name'] as String?,
      thoughtProcess:
          (json['thought_process'] ?? json['thoughtProcess']) as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'role': role};
    if (content != null) map['content'] = content;
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      map['tool_calls'] = toolCalls!.map((tc) => tc.toJson()).toList();
    }
    if (toolCallId != null) map['tool_call_id'] = toolCallId;
    if (name != null) map['name'] = name;
    return map;
  }

  @override
  ChatMessage toDomain() => ChatMessage(
        role: role,
        content: content,
        toolCalls: toolCalls?.map((tc) => tc.toDomain()).toList(),
        toolCallId: toolCallId,
        name: name,
        thoughtProcess: thoughtProcess,
      );
}

class ChatChunkRemoteResponse implements ResponseMapper<ChatChunk> {
  final String? id;
  final String? model;
  final String? contentDelta;
  final List<ToolCallDeltaRemoteResponse>? toolCallDeltas;
  final String? finishReason;

  ChatChunkRemoteResponse({
    this.id,
    this.model,
    this.contentDelta,
    this.toolCallDeltas,
    this.finishReason,
  });

  factory ChatChunkRemoteResponse.fromJson(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return ChatChunkRemoteResponse(
        id: json['id'] as String?,
        model: json['model'] as String?,
      );
    }

    final choice = choices.first as Map<String, dynamic>;
    final delta = choice['delta'] as Map<String, dynamic>?;
    final toolCallsList = delta?['tool_calls'] as List<dynamic>?;

    return ChatChunkRemoteResponse(
      id: json['id'] as String?,
      model: json['model'] as String?,
      contentDelta: delta?['content'] as String?,
      toolCallDeltas: toolCallsList
          ?.map(
            (e) => ToolCallDeltaRemoteResponse.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(),
      finishReason: choice['finish_reason'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (id != null) map['id'] = id;
    if (model != null) map['model'] = model;
    if (contentDelta != null || toolCallDeltas != null) {
      final delta = <String, dynamic>{};
      if (contentDelta != null) delta['content'] = contentDelta;
      if (toolCallDeltas != null && toolCallDeltas!.isNotEmpty) {
        delta['tool_calls'] =
            toolCallDeltas!.map((tc) => tc.toJson()).toList();
      }
      map['choices'] = [
        {'delta': delta, 'finish_reason': finishReason}
      ];
    }
    return map;
  }

  @override
  ChatChunk toDomain() => ChatChunk(
        id: id,
        model: model,
        contentDelta: contentDelta,
        toolCallDeltas: toolCallDeltas?.map((tc) => tc.toDomain()).toList(),
        finishReason: finishReason,
      );
}
