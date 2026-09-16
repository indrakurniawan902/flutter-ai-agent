import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';

/// Contract for persisting imported community skills and skill
/// enable/disable state.
abstract class SkillsLocalDatasourceBase {
  /// Loads every persisted imported skill (newest import last).
  Future<List<Skill>> loadImportedSkills();

  /// Inserts or replaces the persisted payload for [skill].
  Future<void> saveImportedSkill(Skill skill, {String? sourceUrl});

  /// Removes a persisted imported skill.
  Future<void> deleteImportedSkill(String skillId);

  /// Loads persisted enabled/disabled overrides keyed by skill id.
  Future<Map<String, bool>> loadSkillStates();

  /// Persists the enabled state for a single skill.
  Future<void> saveSkillState(String skillId, bool isEnabled);
}
