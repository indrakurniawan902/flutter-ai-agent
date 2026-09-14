import 'dart:io';

import 'package:flutter_ai_agent/data/datasources/local/skills/skills_local_datasource.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late String dbPath;
  late SkillsLocalDatasource datasource;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('skills_ds_test');
    dbPath = '${tempDir.path}/flames_skills.db';
    datasource = SkillsLocalDatasource(
      databaseFactory: databaseFactoryFfi,
      databasePath: dbPath,
    );
  });

  tearDown(() async {
    try {
      if (await File(dbPath).exists()) {
        final db = await datasource.database;
        if (db.isOpen) {
          await db.close();
        }
      }
    } catch (_) {}
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  const testSkill = Skill(
    id: 'community_notes',
    name: 'community_notes',
    description: 'Organize notes quickly',
    category: 'Productivity',
    tier: 'Tier 1 Auto',
    version: '2.1.0',
    author: 'Community',
    tools: ['tool_a', 'tool_b'],
    prompts: ['Prompt one', 'Prompt two'],
    instructions: 'Follow these steps.',
    isEnabled: true,
    isCommunity: true,
  );

  test('save then load round-trips every field', () async {
    await datasource.saveImportedSkill(
      testSkill,
      sourceUrl: 'https://example.com/SKILL.md',
    );

    final loaded = await datasource.loadImportedSkills();

    expect(loaded.length, 1);
    final back = loaded.first;
    expect(back.id, testSkill.id);
    expect(back.name, testSkill.name);
    expect(back.description, testSkill.description);
    expect(back.category, testSkill.category);
    expect(back.tier, testSkill.tier);
    expect(back.version, testSkill.version);
    expect(back.author, testSkill.author);
    expect(back.tools, testSkill.tools);
    expect(back.prompts, testSkill.prompts);
    expect(back.instructions, testSkill.instructions);
    expect(back.isEnabled, testSkill.isEnabled);
    expect(back.isCommunity, testSkill.isCommunity);
  });

  test('skills survive restart on a fresh instance', () async {
    await datasource.saveImportedSkill(testSkill);
    final db = await datasource.database;
    await db.close();

    final fresh = SkillsLocalDatasource(
      databaseFactory: databaseFactoryFfi,
      databasePath: dbPath,
    );
    try {
      final loaded = await fresh.loadImportedSkills();
      expect(loaded.length, 1);
      expect(loaded.first.id, testSkill.id);
      expect(loaded.first.description, testSkill.description);
    } finally {
      try {
        final freshDb = await fresh.database;
        if (freshDb.isOpen) {
          await freshDb.close();
        }
      } catch (_) {}
    }
  });

  test('saving twice replaces rather than duplicates', () async {
    await datasource.saveImportedSkill(testSkill);
    await datasource.saveImportedSkill(
      testSkill.copyWith(description: 'Updated description'),
    );

    final loaded = await datasource.loadImportedSkills();

    expect(loaded.length, 1);
    expect(loaded.first.description, 'Updated description');
  });

  test('delete removes the persisted skill', () async {
    await datasource.saveImportedSkill(testSkill);
    expect(await datasource.loadImportedSkills(), hasLength(1));

    await datasource.deleteImportedSkill(testSkill.id);

    expect(await datasource.loadImportedSkills(), isEmpty);
  });

  test('corrupt payload row is skipped', () async {
    await datasource.saveImportedSkill(testSkill);
    final db = await datasource.database;
    await db.insert(SkillsLocalDatasource.importedTableName, {
      'id': 'corrupt_row',
      'name': 'corrupt_row',
      'payload': 'not-json{{{',
      'source_url': null,
      'imported_at': DateTime.now().millisecondsSinceEpoch,
    });

    final loaded = await datasource.loadImportedSkills();

    expect(loaded.length, 1);
    expect(loaded.first.id, testSkill.id);
  });

  test('skill states round-trip with single row per id', () async {
    await datasource.saveSkillState('skill_a', true);
    await datasource.saveSkillState('skill_b', false);

    var states = await datasource.loadSkillStates();
    expect(states['skill_a'], isTrue);
    expect(states['skill_b'], isFalse);

    await datasource.saveSkillState('skill_a', false);
    states = await datasource.loadSkillStates();
    expect(states['skill_a'], isFalse);
    expect(states['skill_b'], isFalse);

    final db = await datasource.database;
    final rows = await db.query(
      SkillsLocalDatasource.statesTableName,
      where: 'id = ?',
      whereArgs: ['skill_a'],
    );
    expect(rows.length, 1);
  });

  test('upgrade from v1 creates imported skills table', () async {
    final v1 = await databaseFactoryFfi.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE skill_states (
              id TEXT PRIMARY KEY,
              is_enabled INTEGER NOT NULL
            );
          ''');
        },
      ),
    );
    await v1.insert('skill_states', {'id': 'legacy_skill', 'is_enabled': 0});
    await v1.close();

    final upgraded = SkillsLocalDatasource(
      databaseFactory: databaseFactoryFfi,
      databasePath: dbPath,
    );
    try {
      final states = await upgraded.loadSkillStates();
      expect(states['legacy_skill'], isFalse);

      final db = await upgraded.database;
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name = 'imported_skills'",
      );
      expect(tables.length, 1);

      await upgraded.saveImportedSkill(testSkill);
      expect(await upgraded.loadImportedSkills(), hasLength(1));
    } finally {
      try {
        final db = await upgraded.database;
        if (db.isOpen) {
          await db.close();
        }
      } catch (_) {}
    }
  });
}
