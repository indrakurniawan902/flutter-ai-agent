import 'package:equatable/equatable.dart';

/// Represents a persistent memory item stored in device SQLite database.
class MemoryItem extends Equatable {
  final int? id;
  final String key;
  final String content;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final double? score;

  const MemoryItem({
    this.id,
    required this.key,
    required this.content,
    this.tags = const [],
    required this.createdAt,
    required this.updatedAt,
    this.score,
  });

  MemoryItem copyWith({
    int? id,
    String? key,
    String? content,
    List<String>? tags,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? score,
  }) {
    return MemoryItem(
      id: id ?? this.id,
      key: key ?? this.key,
      content: content ?? this.content,
      tags: tags ?? this.tags,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      score: score ?? this.score,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'key': key,
      'content': content,
      'tags': tags,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (score != null) 'score': score,
    };
  }

  factory MemoryItem.fromJson(Map<String, dynamic> json) {
    List<String> parseTags(dynamic rawTags) {
      if (rawTags is List) {
        return rawTags.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
      } else if (rawTags is String && rawTags.isNotEmpty) {
        return rawTags
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      }
      return const [];
    }

    DateTime parseDateTime(dynamic raw, DateTime fallback) {
      if (raw == null) return fallback;
      if (raw is num) {
        return DateTime.fromMillisecondsSinceEpoch(raw.toInt());
      }
      return DateTime.tryParse(raw.toString()) ?? fallback;
    }

    final now = DateTime.now();

    return MemoryItem(
      id: (json['id'] as num?)?.toInt(),
      key: json['key']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      tags: parseTags(json['tags']),
      createdAt: parseDateTime(json['createdAt'] ?? json['created_at'], now),
      updatedAt: parseDateTime(json['updatedAt'] ?? json['updated_at'], now),
      score: (json['score'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      if (id != null) 'id': id,
      'key': key,
      'content': content,
      'tags': tags.join(','),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory MemoryItem.fromDbMap(Map<String, dynamic> map, [double? score]) {
    final tagsRaw = map['tags']?.toString() ?? '';
    final tags = tagsRaw.isEmpty
        ? <String>[]
        : tagsRaw
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

    final createdAtEpoch = (map['created_at'] as num?)?.toInt() ?? 0;
    final updatedAtEpoch = (map['updated_at'] as num?)?.toInt() ?? 0;

    final parsedScore = score ?? (map['rank'] as num?)?.toDouble();

    return MemoryItem(
      id: (map['id'] as num?)?.toInt() ?? (map['rowid'] as num?)?.toInt(),
      key: map['key']?.toString() ?? '',
      content: map['content']?.toString() ?? '',
      tags: tags,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtEpoch),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAtEpoch),
      score: parsedScore,
    );
  }

  @override
  List<Object?> get props => [
        id,
        key,
        content,
        tags,
        createdAt,
        updatedAt,
        score,
      ];
}
