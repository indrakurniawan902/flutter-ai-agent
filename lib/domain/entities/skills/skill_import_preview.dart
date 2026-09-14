import 'package:equatable/equatable.dart';

import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill_scan.dart';

/// Preview of a remote skill import before registration.
class SkillImportPreview extends Equatable {
  final String sourceUrl;
  final Skill skill;
  final String rawMarkdown;
  final SkillScanResult scan;

  const SkillImportPreview({
    required this.sourceUrl,
    required this.skill,
    required this.rawMarkdown,
    required this.scan,
  });

  /// Whether the preview passed the security scan.
  bool get canImport => scan.isClean;

  /// Estimate of injected prompt chars for this skill.
  int get estimatedPromptChars {
    var total = skill.description.length + skill.instructions.length;
    for (final p in skill.prompts) {
      total += p.length + 4;
    }
    if (skill.tools.isNotEmpty) {
      total += 'Available Tools: '.length + skill.tools.join(', ').length + 1;
    }
    total += skill.name.length + skill.category.length + skill.version.length;
    return total + 8;
  }

  @override
  List<Object?> get props => [sourceUrl, skill, rawMarkdown, scan];
}
