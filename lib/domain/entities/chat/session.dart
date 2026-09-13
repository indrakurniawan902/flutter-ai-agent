import 'package:equatable/equatable.dart';

/// A chat session belonging to a server profile.
///
/// Sessions group a conversation's messages so history can be keyed by
/// `sessionId` instead of only by `profileId`.
class Session extends Equatable {
  final int id;
  final String profileId;
  final String title;
  final int createdAt;
  final int updatedAt;

  const Session({
    required this.id,
    required this.profileId,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  Session copyWith({
    int? id,
    String? profileId,
    String? title,
    int? createdAt,
    int? updatedAt,
  }) {
    return Session(
      id: id ?? this.id,
      profileId: profileId ?? this.profileId,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      id: (json['id'] as num).toInt(),
      profileId: json['profile_id'] as String,
      title: json['title'] as String,
      createdAt: (json['created_at'] as num).toInt(),
      updatedAt: (json['updated_at'] as num).toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'profile_id': profileId,
      'title': title,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  @override
  List<Object?> get props => [id, profileId, title, createdAt, updatedAt];
}
