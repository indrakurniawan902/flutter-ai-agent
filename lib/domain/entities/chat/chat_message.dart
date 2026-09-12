import 'package:equatable/equatable.dart';
import 'tool_call_delta.dart';
import 'package:flutter_ai_agent/domain/models/chat/action_step.dart';
import 'package:flutter_ai_agent/domain/models/chat/generative_card_data.dart';

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
    if (thoughtProcess != null) {
      map['thought_process'] = thoughtProcess;
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
