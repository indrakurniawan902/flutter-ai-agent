import 'package:equatable/equatable.dart';

/// Represents a pending tool call that requires user approval (Tier 3 HITL).
class ToolCallRequest extends Equatable {
  final String id;
  final String name;
  final Map<String, dynamic> parameters;

  const ToolCallRequest({
    required this.id,
    required this.name,
    required this.parameters,
  });

  @override
  List<Object?> get props => [id, name, parameters];
}
