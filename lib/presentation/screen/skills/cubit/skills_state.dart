import 'package:equatable/equatable.dart';

import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';

abstract class SkillsState extends Equatable {
  const SkillsState();

  @override
  List<Object?> get props => [];
}

class SkillsInitial extends SkillsState {
  const SkillsInitial();
}

class SkillsLoading extends SkillsState {
  const SkillsLoading();
}

class SkillsLoaded extends SkillsState {
  final List<Skill> allSkills;
  final List<Skill> filteredSkills;
  final String selectedCategory;
  final String searchQuery;
  final int activeCount;

  const SkillsLoaded({
    required this.allSkills,
    required this.filteredSkills,
    this.selectedCategory = 'all',
    this.searchQuery = '',
    required this.activeCount,
  });

  SkillsLoaded copyWith({
    List<Skill>? allSkills,
    List<Skill>? filteredSkills,
    String? selectedCategory,
    String? searchQuery,
    int? activeCount,
  }) {
    return SkillsLoaded(
      allSkills: allSkills ?? this.allSkills,
      filteredSkills: filteredSkills ?? this.filteredSkills,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      searchQuery: searchQuery ?? this.searchQuery,
      activeCount: activeCount ?? this.activeCount,
    );
  }

  @override
  List<Object?> get props => [
        allSkills,
        filteredSkills,
        selectedCategory,
        searchQuery,
        activeCount,
      ];
}

class SkillsError extends SkillsState {
  final String message;

  const SkillsError(this.message);

  @override
  List<Object?> get props => [message];
}
