import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/services/skills/skill_import_service.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_state.dart';

/// Presentation Cubit managing state for Skills Hub screen.
@injectable
class SkillsCubit extends Cubit<SkillsState> {
  final SkillsRegistryService _skillsRegistryService;
  final SkillImportService? _skillImportService;

  SkillsCubit({
    required SkillsRegistryService skillsRegistryService,
    SkillImportService? skillImportService,
    @ignoreParam bool autoLoad = true,
  })  : _skillsRegistryService = skillsRegistryService,
        _skillImportService = skillImportService,
        super(const SkillsInitial()) {
    if (autoLoad) {
      loadSkills();
    }
  }

  /// Loads all registered skills from the registry.
  Future<void> loadSkills() async {
    emit(const SkillsLoading());
    try {
      await _skillsRegistryService.hydrateFromStorage();
      final all = _skillsRegistryService.getAllSkills();
      emit(SkillsLoaded(
        allSkills: all,
        filteredSkills: all,
        selectedCategory: 'all',
        searchQuery: '',
        activeCount: _skillsRegistryService.getActiveSkills().length,
      ));
    } catch (e) {
      emit(SkillsError(
          FailureMessage.humanize(e, context: 'Failed to load skills')));
    }
  }

  /// Selects a category filter pill and updates filtered skills.
  void selectCategory(String category) {
    if (state is! SkillsLoaded) return;
    final current = state as SkillsLoaded;
    final normalized = category.toLowerCase();

    final filtered = _filter(
      current.allSkills,
      normalized,
      current.searchQuery,
    );

    emit(current.copyWith(
      selectedCategory: normalized,
      filteredSkills: filtered,
    ));
  }

  /// Updates the search query and filters the skills list.
  void search(String query) {
    if (state is! SkillsLoaded) return;
    final current = state as SkillsLoaded;
    final trimmed = query.trim().toLowerCase();

    final filtered = _filter(
      current.allSkills,
      current.selectedCategory,
      trimmed,
    );

    emit(current.copyWith(
      searchQuery: trimmed,
      filteredSkills: filtered,
    ));
  }

  /// Toggles a skill's enabled state.
  void toggleSkill(String skillIdOrName, bool enabled) {
    _skillsRegistryService.setSkillEnabled(skillIdOrName, enabled);
    final all = _skillsRegistryService.getAllSkills();

    if (state is SkillsLoaded) {
      final current = state as SkillsLoaded;
      final filtered = _filter(
        all,
        current.selectedCategory,
        current.searchQuery,
      );
      emit(current.copyWith(
        allSkills: all,
        filteredSkills: filtered,
        activeCount: _skillsRegistryService.getActiveSkills().length,
      ));
    } else {
      emit(SkillsLoaded(
        allSkills: all,
        filteredSkills: all,
        activeCount: _skillsRegistryService.getActiveSkills().length,
      ));
    }
  }

  /// Parses and registers a skill definition from Markdown.
  void registerSkillFromMarkdown(String markdownContent) {
    _skillsRegistryService.registerSkillFromMarkdown(markdownContent);
    loadSkills();
  }

  /// Registers an explicit Skill entity.
  void registerSkill(Skill skill) {
    _skillsRegistryService.registerSkill(skill);
    loadSkills();
  }

  /// Fetches and security-scans the remote SKILL.md at [url],
  /// then publishes a preview. Never registers anything.
  Future<void> importSkillFromUrl(String url) async {
    if (state is! SkillsLoaded) return;
    final service = _skillImportService;
    if (service == null) {
      final current = state as SkillsLoaded;
      emit(current.copyWith(
        importBusy: false,
        importError: 'Remote skill import is unavailable.',
      ));
      return;
    }
    final current = state as SkillsLoaded;
    emit(SkillsLoaded(
      allSkills: current.allSkills,
      filteredSkills: current.filteredSkills,
      selectedCategory: current.selectedCategory,
      searchQuery: current.searchQuery,
      activeCount: current.activeCount,
      importBusy: true,
    ));
    final res = await service.buildPreview(url);
    if (state is! SkillsLoaded) return;
    final latest = state as SkillsLoaded;
    res.fold(
      (f) => emit(latest.copyWith(
        importBusy: false,
        importError: f.message,
      )),
      (preview) => emit(SkillsLoaded(
        allSkills: latest.allSkills,
        filteredSkills: latest.filteredSkills,
        selectedCategory: latest.selectedCategory,
        searchQuery: latest.searchQuery,
        activeCount: latest.activeCount,
        importBusy: false,
        importPreview: preview,
      )),
    );
  }

  /// Registers the pending preview when it is safe; clears pending state.
  /// Returns the registered skill, or null when nothing was registered.
  Future<Skill?> confirmSkillImport() async {
    if (state is! SkillsLoaded) return null;
    final current = state as SkillsLoaded;
    final preview = current.importPreview;
    if (preview == null) return null;
    final service = _skillImportService;
    if (service == null) {
      emit(current.copyWith(
        importBusy: false,
        importError: 'Remote skill import is unavailable.',
      ));
      return null;
    }
    if (!preview.canImport) {
      emit(current.copyWith(
        importBusy: false,
        importError: preview.scan.rejectionReason ??
            'Skill rejected by security scan',
      ));
      return null;
    }
    final res = await service.confirmImport(preview);
    Skill? ok;
    res.fold(
      (f) {
        if (state is! SkillsLoaded) return;
        final latest = state as SkillsLoaded;
        emit(latest.copyWith(
          importBusy: false,
          importError: f.message,
        ));
      },
      (skill) => ok = skill,
    );
    if (ok == null) return null;
    await loadSkills();
    return ok;
  }

  /// Drops the pending preview / error without registering.
  void clearSkillImport() {
    if (state is! SkillsLoaded) return;
    final current = state as SkillsLoaded;
    emit(SkillsLoaded(
      allSkills: current.allSkills,
      filteredSkills: current.filteredSkills,
      selectedCategory: current.selectedCategory,
      searchQuery: current.searchQuery,
      activeCount: current.activeCount,
    ));
  }

  List<Skill> _filter(
    List<Skill> skills,
    String category,
    String query,
  ) {
    return skills.where((skill) {
      final matchesCat = _matchesCategory(skill.category, category);
      final matchesQuery = query.isEmpty ||
          skill.name.toLowerCase().contains(query) ||
          skill.description.toLowerCase().contains(query) ||
          skill.tools.any((t) => t.toLowerCase().contains(query));
      return matchesCat && matchesQuery;
    }).toList();
  }

  bool _matchesCategory(String skillCategory, String filterCategory) {
    final sCat = skillCategory.toLowerCase();
    final fCat = filterCategory.toLowerCase();
    if (fCat == 'all') return true;
    if (sCat == fCat) return true;
    if (fCat == 'device' && (sCat == 'device' || sCat == 'device control')) {
      return true;
    }
    if (fCat == 'automations' && sCat.contains('automat')) return true;
    if (fCat == 'automation' && sCat.contains('automat')) return true;
    return false;
  }
}
