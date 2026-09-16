import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/data/datasources/local/skills/skills_local_datasource.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  final sources = <SkillsLocalDatasource>[];

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('skills_reg_test');
    dbPath = '${tempDir.path}/flames_skills.db';
    sources.clear();
  });

  tearDown(() async {
    for (final ds in sources) {
      try {
        final db = await ds.database;
        if (db.isOpen) {
          await db.close();
        }
      } catch (_) {}
    }
    sources.clear();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  SkillsLocalDatasource makeDatasource() {
    final ds = SkillsLocalDatasource(
      databaseFactory: databaseFactoryFfi,
      databasePath: dbPath,
    );
    sources.add(ds);
    return ds;
  }

  Future<void> closeSources() async {
    for (final ds in sources) {
      try {
        final db = await ds.database;
        if (db.isOpen) {
          await db.close();
        }
      } catch (_) {}
    }
    sources.clear();
  }

  const importedSkill = Skill(
    id: 'community_notes',
    name: 'community_notes',
    description: 'Organize notes quickly',
    category: 'Productivity',
    tier: 'Tier 1 Auto',
    version: '1.0.0',
    author: 'Community',
    tools: [],
    prompts: [],
    instructions: 'Follow these steps.',
    isEnabled: true,
    isCommunity: true,
  );

  test('imported skill survives restart with state', () async {
    final dsA = makeDatasource();
    final a = SkillsRegistryService(loadDefaults: false, localDatasource: dsA);
    await a.registerImportedSkill(
      importedSkill,
      sourceUrl: 'https://example.com/SKILL.md',
    );
    await closeSources();

    final dsB = makeDatasource();
    final b = SkillsRegistryService(loadDefaults: false, localDatasource: dsB);
    final ok = await b.hydrateFromStorage();

    expect(ok, isTrue);
    final back = b.getSkill(importedSkill.id);
    expect(back, isNotNull);
    expect(back!.isCommunity, isTrue);
    expect(back.isEnabled, isTrue);
  });

  test('persisted disabled override survives restart', () async {
    final dsA = makeDatasource();
    final a = SkillsRegistryService(loadDefaults: false, localDatasource: dsA);
    await a.registerImportedSkill(importedSkill);
    a.setSkillEnabled(importedSkill.id, false);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await closeSources();

    final dsB = makeDatasource();
    final b = SkillsRegistryService(loadDefaults: false, localDatasource: dsB);
    await b.hydrateFromStorage();

    expect(b.isSkillEnabled(importedSkill.id), isFalse);
  });

  test('hydrate is idempotent without duplicates', () async {
    final dsA = makeDatasource();
    final a = SkillsRegistryService(loadDefaults: false, localDatasource: dsA);
    await a.registerImportedSkill(importedSkill);
    await closeSources();

    final dsB = makeDatasource();
    final b = SkillsRegistryService(loadDefaults: false, localDatasource: dsB);

    expect(await b.hydrateFromStorage(), isTrue);
    expect(await b.hydrateFromStorage(), isTrue);
    expect(b.getAllSkills().where((s) => s.id == importedSkill.id).length, 1);
  });

  test('hydrate without datasource returns false', () async {
    final registry = SkillsRegistryService(loadDefaults: false);

    expect(await registry.hydrateFromStorage(), isFalse);
  });

  test('disabled imported skill does not leak tools', () async {
    final ds = makeDatasource();
    final registry = SkillsRegistryService(
      loadDefaults: false,
      localDatasource: ds,
    );
    const offSkill = Skill(
      id: 'imported_off',
      name: 'imported_off',
      description: 'Imported tool skill',
      tools: ['imported_tool'],
      isEnabled: false,
      isCommunity: true,
    );
    await registry.registerImportedSkill(offSkill);

    final toolRegistry = ToolRegistry();
    toolRegistry.register(
      RegisteredTool(
        name: 'imported_tool',
        description: 'Imported tool',
        parameters: const {'type': 'object'},
        securityTier: SecurityTier.tier1Auto,
        execute: (_) async => const Right('ok'),
      ),
    );

    registry.syncWithToolRegistry(toolRegistry);
    expect(toolRegistry.isToolEnabled('imported_tool'), isFalse);
    expect(
      toolRegistry.getOpenAiToolDefinitions().any(
        (t) =>
            (t['function'] as Map<String, dynamic>)['name'] == 'imported_tool',
      ),
      isFalse,
    );

    registry.setSkillEnabled(offSkill.id, true);
    registry.syncWithToolRegistry(toolRegistry);
    expect(toolRegistry.isToolEnabled('imported_tool'), isTrue);
    expect(
      toolRegistry.getOpenAiToolDefinitions().any(
        (t) =>
            (t['function'] as Map<String, dynamic>)['name'] == 'imported_tool',
      ),
      isTrue,
    );
  });
}
