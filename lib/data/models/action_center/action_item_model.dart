import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';

/// Data model for [ActionItem] with JSON serialization.
///
/// Persisted to the Hive box as a JSON-encoded string, so no generated
/// TypeAdapter is required.
class ActionItemModel extends ActionItem {
  const ActionItemModel({
    required super.id,
    required super.title,
    required super.summary,
    required super.timestamp,
    super.priority = ActionItemPriority.normal,
    super.isRead = false,
    super.actionPayload,
    required super.source,
  });

  /// Builds a model from a plain [ActionItem] entity.
  factory ActionItemModel.fromEntity(ActionItem entity) {
    return ActionItemModel(
      id: entity.id,
      title: entity.title,
      summary: entity.summary,
      timestamp: entity.timestamp,
      priority: entity.priority,
      isRead: entity.isRead,
      actionPayload: entity.actionPayload,
      source: entity.source,
    );
  }

  /// Parses a camelCase JSON map into an [ActionItemModel].
  factory ActionItemModel.fromJson(Map<String, dynamic> json) {
    final rawPriority = json['priority']?.toString();
    final rawTimestamp = json['timestamp'];
    final rawPayload = json['actionPayload'];

    return ActionItemModel(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      summary: (json['summary'] ?? '').toString(),
      timestamp: rawTimestamp is String
          ? DateTime.tryParse(rawTimestamp) ?? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.fromMillisecondsSinceEpoch(0),
      priority: ActionItemPriority.values.firstWhere(
        (p) => p.name == rawPriority,
        orElse: () => ActionItemPriority.normal,
      ),
      isRead: json['isRead'] == true,
      actionPayload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : null,
      source: (json['source'] ?? '').toString(),
    );
  }

  /// Converts the model into a JSON-compatible map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'summary': summary,
      'timestamp': timestamp.toIso8601String(),
      'priority': priority.name,
      'isRead': isRead,
      'actionPayload': actionPayload,
      'source': source,
    };
  }
}
