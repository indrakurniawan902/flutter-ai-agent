import 'package:equatable/equatable.dart';

/// Delta update for a tool call in a streaming response.
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

  ToolCallDelta copyWith({
    int? index,
    String? id,
    String? name,
    String? argumentsFragment,
  }) {
    return ToolCallDelta(
      index: index ?? this.index,
      id: id ?? this.id,
      name: name ?? this.name,
      argumentsFragment: argumentsFragment ?? this.argumentsFragment,
    );
  }

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
