import 'package:equatable/equatable.dart';

/// Status of an individual action step in the autonomous execution pipeline.
enum ActionStepStatus {
  pending,
  inProgress,
  done,
  error;

  bool get isPending => this == ActionStepStatus.pending;
  bool get isInProgress => this == ActionStepStatus.inProgress;
  bool get isDone => this == ActionStepStatus.done;
  bool get isError => this == ActionStepStatus.error;
}

/// Represents a single action step in a multi-step autonomous execution plan.
class ActionStep extends Equatable {
  final String id;
  final String title;
  final String? description;
  final ActionStepStatus status;
  final Map<String, dynamic>? parameters;
  final dynamic output;
  final String? errorMessage;

  const ActionStep({
    required this.id,
    required this.title,
    this.description,
    this.status = ActionStepStatus.pending,
    this.parameters,
    this.output,
    this.errorMessage,
  });

  ActionStep copyWith({
    String? id,
    String? title,
    String? description,
    ActionStepStatus? status,
    Map<String, dynamic>? parameters,
    dynamic output,
    String? errorMessage,
  }) {
    return ActionStep(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      status: status ?? this.status,
      parameters: parameters ?? this.parameters,
      output: output ?? this.output,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        description,
        status,
        parameters,
        output,
        errorMessage,
      ];
}
