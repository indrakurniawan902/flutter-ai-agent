import 'package:equatable/equatable.dart';
import 'package:flutter_ai_agent/features/chat/domain/models/action_step.dart';
import 'package:flutter_ai_agent/features/chat/domain/models/generative_card_data.dart';

/// Represents a delta update for a tool call in a streaming response.
class ToolCallDelta extends Equatable {
  final int index;
  final String? id;
  final String? name;
  final String argumentsFragment;

  const ToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsFragment = '',
  });

  factory ToolCallDelta.fromJson(Map<String, dynamic> json) {
    final function_ = json['function'] as Map<String, dynamic>?;
    return ToolCallDelta(
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
  List<Object?> get props => [index, id, name, argumentsFragment];
}

/// Result of executing a tool call, sent back to the LLM.
class ToolCallResult extends Equatable {
  final String toolCallId;
  final String name;
  final String content;

  const ToolCallResult({
    required this.toolCallId,
    required this.name,
    required this.content,
  });

  Map<String, dynamic> toJson() => {
        'role': 'tool',
        'tool_call_id': toolCallId,
        'name': name,
        'content': content,
      };

  @override
  List<Object> get props => [toolCallId, name, content];
}

/// A message in the chat conversation.
class ChatMessage extends Equatable {
  final String role;
  final String? content;
  final List<ToolCallDelta>? toolCalls;
  final String? toolCallId;
  final String? name;
  final String? thoughtProcess;
  final List<ActionStep>? actionSteps;
  final ActionConfirmationData? confirmationCard;
  final SummaryCardData? summaryCard;

  const ChatMessage({
    required this.role,
    this.content,
    this.toolCalls,
    this.toolCallId,
    this.name,
    this.thoughtProcess,
    this.actionSteps,
    this.confirmationCard,
    this.summaryCard,
  });

  ChatMessage copyWith({
    String? role,
    String? content,
    List<ToolCallDelta>? toolCalls,
    String? toolCallId,
    String? name,
    String? thoughtProcess,
    List<ActionStep>? actionSteps,
    ActionConfirmationData? confirmationCard,
    SummaryCardData? summaryCard,
  }) {
    return ChatMessage(
      role: role ?? this.role,
      content: content ?? this.content,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId ?? this.toolCallId,
      name: name ?? this.name,
      thoughtProcess: thoughtProcess ?? this.thoughtProcess,
      actionSteps: actionSteps ?? this.actionSteps,
      confirmationCard: confirmationCard ?? this.confirmationCard,
      summaryCard: summaryCard ?? this.summaryCard,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final toolCallsList = json['tool_calls'] as List<dynamic>?;
    return ChatMessage(
      role: json['role'] as String,
      content: json['content'] as String?,
      toolCalls: toolCallsList
          ?.map((e) => ToolCallDelta.fromJson(e as Map<String, dynamic>))
          .toList(),
      toolCallId: json['tool_call_id'] as String?,
      name: json['name'] as String?,
      thoughtProcess: (json['thought_process'] ?? json['thoughtProcess'])
          as String?,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'role': role,
    };
    if (content != null) {
      map['content'] = content;
    }
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      map['tool_calls'] = toolCalls!.map((tc) {
        return {
          if (tc.id != null) 'id': tc.id,
          'type': 'function',
          'function': {
            if (tc.name != null) 'name': tc.name,
            'arguments': tc.argumentsFragment,
          },
        };
      }).toList();
    }
    if (toolCallId != null) {
      map['tool_call_id'] = toolCallId;
    }
    if (name != null) {
      map['name'] = name;
    }
    return map;
  }

  @override
  List<Object?> get props => [
        role,
        content,
        toolCalls,
        toolCallId,
        name,
        thoughtProcess,
        actionSteps,
        confirmationCard,
        summaryCard,
      ];
}

/// A single chunk from an SSE streaming response.
class ChatChunk extends Equatable {
  final String? id;
  final String? model;
  final String? contentDelta;
  final List<ToolCallDelta>? toolCallDeltas;
  final String? finishReason;

  const ChatChunk({
    this.id,
    this.model,
    this.contentDelta,
    this.toolCallDeltas,
    this.finishReason,
  });

  factory ChatChunk.fromJson(Map<String, dynamic> json) {
    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      return ChatChunk(
        id: json['id'] as String?,
        model: json['model'] as String?,
      );
    }

    final choice = choices.first as Map<String, dynamic>;
    final delta = choice['delta'] as Map<String, dynamic>?;
    final toolCallsList = delta?['tool_calls'] as List<dynamic>?;

    return ChatChunk(
      id: json['id'] as String?,
      model: json['model'] as String?,
      contentDelta: delta?['content'] as String?,
      toolCallDeltas: toolCallsList
          ?.map((e) => ToolCallDelta.fromJson(e as Map<String, dynamic>))
          .toList(),
      finishReason: choice['finish_reason'] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [id, model, contentDelta, toolCallDeltas, finishReason];
}
