import 'package:equatable/equatable.dart';
import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';

/// Immutable state for [ActionCenterCubit].
class ActionCenterState extends Equatable {
  /// Inbox items, newest-first.
  final List<ActionItem> items;

  /// True while an inbox read/write is in flight.
  final bool isLoading;

  /// Human-readable failure from the last operation, if any.
  final String? error;

  /// Id of the most recent item whose action was executed, if any.
  final String? lastExecutedActionId;

  const ActionCenterState({
    this.items = const [],
    this.isLoading = false,
    this.error,
    this.lastExecutedActionId,
  });

  /// Unread items only.
  List<ActionItem> get unread =>
      items.where((item) => !item.isRead).toList(growable: false);

  ActionCenterState copyWith({
    List<ActionItem>? items,
    bool? isLoading,
    String? error,
    bool clearError = false,
    String? lastExecutedActionId,
  }) {
    return ActionCenterState(
      items: items ?? this.items,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      lastExecutedActionId: lastExecutedActionId ?? this.lastExecutedActionId,
    );
  }

  @override
  List<Object?> get props =>
      [items, isLoading, error, lastExecutedActionId];
}
