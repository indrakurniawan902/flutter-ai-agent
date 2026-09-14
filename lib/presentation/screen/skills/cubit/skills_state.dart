import 'package:equatable/equatable.dart';

import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill_import_preview.dart';

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
  final bool importBusy;
  final SkillImportPreview? importPreview;
  final String? importError;

  const SkillsLoaded({
    required this.allSkills,
    required this.filteredSkills,
    this.selectedCategory = 'all',
    this.searchQuery = '',
    required this.activeCount,
    this.importBusy = false,
    this.importPreview,
    this.importError,
  });

  SkillsLoaded copyWith({
    List<Skill>? allSkills,
    List<Skill>? filteredSkills,
    String? selectedCategory,
    String? searchQuery,
    int? activeCount,
    bool? importBusy,
    bool clearImportPreview = false,
    SkillImportPreview? importPreview,
    String? importError,
  }) {
    return SkillsLoaded(
      allSkills: allSkills ?? this.allSkills,
      filteredSkills: filteredSkills ?? this.filteredSkills,
      selectedCategory: selectedCategory ?? this.selectedCategory,
      searchQuery: searchQuery ?? this.searchQuery,
      activeCount: activeCount ?? this.activeCount,
      importBusy: importBusy ?? this.importBusy,
      importPreview:
          clearImportPreview ? null : (importPreview ?? this.importPreview),
      importError: importError ?? this.importError,
    );
  }

  @override
  List<Object?> get props => [
        allSkills,
        filteredSkills,
        selectedCategory,
        searchQuery,
        activeCount,
        importBusy,
        importPreview,
        importError,
      ];
}

class SkillsError extends SkillsState {
  final String message;

  const SkillsError(this.message);

  @override
  List<Object?> get props => [message];
}
