import 'package:equatable/equatable.dart';
import 'tool_call_delta.dart';

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
