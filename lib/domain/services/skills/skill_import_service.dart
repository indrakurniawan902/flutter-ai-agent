import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill_import_preview.dart';
import 'package:flutter_ai_agent/domain/services/skills/skill_remote_loader.dart';
import 'package:flutter_ai_agent/domain/services/skills/skill_security_scanner.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';

/// Builds import previews for remote skills and confirms safe imports.
@lazySingleton
class SkillImportService {
  final SkillRemoteLoaderBase _loader;
  final SkillsRegistryService _registry;
  final SkillSecurityScanner _scanner;
  final ToolRegistry _toolRegistry;

  SkillImportService({
    required SkillRemoteLoaderBase loader,
    required SkillsRegistryService registry,
    required SkillSecurityScanner scanner,
    required ToolRegistry toolRegistry,
  }) : _loader = loader,
       _registry = registry,
       _scanner = scanner,
       _toolRegistry = toolRegistry;

  /// Fetches, parses and scans a remote skill without registering it.
  Future<Either<Failure, SkillImportPreview>> buildPreview(String url) async {
    final normalized = SkillRemoteLoaderBase.normalizeSkillSourceUrl(url);
    final invalid = SkillRemoteLoaderBase.validateSourceUrl(normalized);
    if (invalid != null) {
      return Left(ParseFailure(invalid));
    }
    final fetched = await _loader.fetchSkillMarkdown(normalized);
    if (fetched.isLeft()) {
      return Left(fetched.fold((l) => l, (_) => const ParseFailure('Fetch')));
    }
    final markdown = fetched.getOrElse(() => '');
    final parsed = _registry.parseSkillFromMarkdown(markdown);
    final skill = parsed.copyWith(isCommunity: true);
    final registeredToolNames = _toolRegistry.tools.map((t) => t.name).toSet();
    final scan = _scanner.scan(
      skill: skill,
      registeredToolNames: registeredToolNames,
    );
    return Right(
      SkillImportPreview(
        sourceUrl: normalized,
        skill: skill,
        rawMarkdown: markdown,
        scan: scan,
      ),
    );
  }

  /// Registers [preview] only when the scan passed.
  Future<Either<Failure, Skill>> confirmImport(
    SkillImportPreview preview,
  ) async {
    if (!preview.canImport) {
      return Left(
        ValidationFailure(
          preview.scan.rejectionReason ?? 'Skill rejected by security scan',
        ),
      );
    }
    final applied = _scanner.applyImportPolicy(preview.skill);
    await _registry.registerImportedSkill(
      applied,
      sourceUrl: preview.sourceUrl,
    );
    return Right(applied);
  }
}
