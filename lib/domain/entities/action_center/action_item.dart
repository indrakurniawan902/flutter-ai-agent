import 'package:equatable/equatable.dart';

/// Urgency of an [ActionItem] surfaced in the Action Center inbox.
enum ActionItemPriority { low, normal, high }

/// A single actionable notification awaiting user attention in the
/// Action Center inbox.
class ActionItem extends Equatable {
  final String id;
  final String title;
  final String summary;
  final DateTime timestamp;
  final ActionItemPriority priority;
  final bool isRead;
  final Map<String, dynamic>? actionPayload;
  final String source;

  const ActionItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.timestamp,
    this.priority = ActionItemPriority.normal,
    this.isRead = false,
    this.actionPayload,
    required this.source,
  });

  ActionItem copyWith({
    String? id,
    String? title,
    String? summary,
    DateTime? timestamp,
    ActionItemPriority? priority,
    bool? isRead,
    Map<String, dynamic>? actionPayload,
    String? source,
  }) {
    return ActionItem(
      id: id ?? this.id,
      title: title ?? this.title,
      summary: summary ?? this.summary,
      timestamp: timestamp ?? this.timestamp,
      priority: priority ?? this.priority,
      isRead: isRead ?? this.isRead,
      actionPayload: actionPayload ?? this.actionPayload,
      source: source ?? this.source,
    );
  }

  @override
  List<Object?> get props => [
        id,
        title,
        summary,
        timestamp,
        priority,
        isRead,
        actionPayload,
        source,
      ];
}
