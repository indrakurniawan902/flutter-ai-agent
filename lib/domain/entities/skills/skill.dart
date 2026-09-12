import 'package:equatable/equatable.dart';

/// Represents a modular agent capability/skill definition.
class Skill extends Equatable {
  final String id;
  final String name;
  final String description;
  final String category;
  final String tier;
  final String version;
  final String author;
  final List<String> tools;
  final List<String> prompts;
  final String instructions;
  final bool isEnabled;
  final bool isCommunity;

  const Skill({
    required this.id,
    required this.name,
    required this.description,
    this.category = 'Productivity',
    this.tier = 'Tier 1 Auto',
    this.version = '1.0.0',
    this.author = 'Flames',
    this.tools = const [],
    this.prompts = const [],
    this.instructions = '',
    this.isEnabled = true,
    this.isCommunity = false,
  });

  Skill copyWith({
    String? id,
    String? name,
    String? description,
    String? category,
    String? tier,
    String? version,
    String? author,
    List<String>? tools,
    List<String>? prompts,
    String? instructions,
    bool? isEnabled,
    bool? isCommunity,
  }) {
    return Skill(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      category: category ?? this.category,
      tier: tier ?? this.tier,
      version: version ?? this.version,
      author: author ?? this.author,
      tools: tools ?? this.tools,
      prompts: prompts ?? this.prompts,
      instructions: instructions ?? this.instructions,
      isEnabled: isEnabled ?? this.isEnabled,
      isCommunity: isCommunity ?? this.isCommunity,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'category': category,
      'tier': tier,
      'version': version,
      'author': author,
      'tools': tools,
      'prompts': prompts,
      'instructions': instructions,
      'is_enabled': isEnabled,
      'is_community': isCommunity,
    };
  }

  factory Skill.fromJson(Map<String, dynamic> json) {
    return Skill(
      id: json['id'] as String? ?? json['name'] as String? ?? 'unnamed_skill',
      name: json['name'] as String? ?? 'unnamed_skill',
      description: json['description'] as String? ?? '',
      category: json['category'] as String? ?? 'Productivity',
      tier: json['tier'] as String? ?? 'Tier 1 Auto',
      version: json['version'] as String? ?? '1.0.0',
      author: json['author'] as String? ?? 'Flames',
      tools: (json['tools'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      prompts: (json['prompts'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      instructions: json['instructions'] as String? ?? '',
      isEnabled: json['is_enabled'] as bool? ??
          json['isEnabled'] as bool? ??
          true,
      isCommunity: json['is_community'] as bool? ??
          json['isCommunity'] as bool? ??
          false,
    );
  }

  @override
  List<Object?> get props => [
        id,
        name,
        description,
        category,
        tier,
        version,
        author,
        tools,
        prompts,
        instructions,
        isEnabled,
        isCommunity,
      ];
}
