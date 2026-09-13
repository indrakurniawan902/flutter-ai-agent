import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'tool_call_delta.dart';
import 'chat_attachment.dart';
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
  final List<ChatAttachment>? attachments;

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
    this.attachments,
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
    List<ChatAttachment>? attachments,
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
      attachments: attachments ?? this.attachments,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final toolCallsList = json['tool_calls'] as List<dynamic>?;
    final attachmentsList = json['attachments'] as List<dynamic>?;
    return ChatMessage(
      role: json['role'] as String,
      content: _parseContent(json['content']),
      toolCalls: toolCallsList
          ?.map((e) => ToolCallDelta.fromJson(e as Map<String, dynamic>))
          .toList(),
      toolCallId: json['tool_call_id'] as String?,
      name: json['name'] as String?,
      thoughtProcess: (json['thought_process'] ?? json['thoughtProcess'])
          as String?,
      attachments: attachmentsList
          ?.whereType<Map<String, dynamic>>()
          .map(ChatAttachment.fromJson)
          .toList(),
    );
  }

  static String? _parseContent(dynamic raw) {
    if (raw == null) return null;
    if (raw is String) return raw;
    if (raw is List) {
      final buffer = StringBuffer();
      for (final part in raw) {
        if (part is Map && part['type'] == 'text' && part['text'] is String) {
          if (buffer.isNotEmpty) buffer.write('\n\n');
          buffer.write(part['text'] as String);
        }
      }
      return buffer.toString();
    }
    return raw.toString();
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{
      'role': role,
    };
    if (attachments != null && attachments!.isNotEmpty) {
      map['content'] = _buildMultipartContent();
      map['attachments'] = attachments!.map((a) => a.toJson()).toList();
    } else if (content != null) {
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

  List<Map<String, dynamic>> _buildMultipartContent() {
    final textBuffer = StringBuffer(content ?? '');
    for (final attachment in attachments!) {
      if (attachment.type != ChatAttachmentType.file) continue;
      textBuffer.write('\n\n[Attached file: ${attachment.filename}]\n');
      textBuffer.write(_decodeAttachment(attachment));
    }

    final parts = <Map<String, dynamic>>[];
    if (textBuffer.isNotEmpty) {
      parts.add({'type': 'text', 'text': textBuffer.toString()});
    }
    for (final attachment in attachments!) {
      if (attachment.type != ChatAttachmentType.image) continue;
      parts.add({
        'type': 'image_url',
        'image_url': {'url': attachment.dataUrl},
      });
    }
    return parts;
  }

  static String _decodeAttachment(ChatAttachment attachment) {
    try {
      return utf8.decode(
        base64Decode(attachment.base64Data),
        allowMalformed: true,
      );
    } catch (_) {
      return attachment.base64Data;
    }
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
        attachments,
      ];
}
