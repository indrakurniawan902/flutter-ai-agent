import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_local_datasource.dart';

/// Sqflite-backed persistence for imported community skills and
/// skill enabled/disabled overrides.
@LazySingleton(as: SkillsLocalDatasourceBase)
class SkillsLocalDatasource implements SkillsLocalDatasourceBase {
  static const int currentSchemaVersion = 2;
  static const String databaseFileName = 'flames_skills.db';
  static const String statesTableName = 'skill_states';
  static const String importedTableName = 'imported_skills';

  Database? _database;
  final DatabaseFactory? _databaseFactory;
  final String? _databasePath;

  SkillsLocalDatasource({
    Database? database,
    DatabaseFactory? databaseFactory,
    String? databasePath,
  }) : _database = database,
       _databaseFactory = databaseFactory,
       _databasePath = databasePath;

  @factoryMethod
  factory SkillsLocalDatasource.create() => SkillsLocalDatasource();

  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    DatabaseFactory factory;
    if (_databaseFactory != null) {
      factory = _databaseFactory;
    } else {
      if (Platform.isAndroid) {
        databaseFactory = databaseFactoryFfi;
      }
      factory = databaseFactory;
    }
    final String path;
    final configuredPath = _databasePath;
    if (configuredPath != null) {
      path = configuredPath;
    } else {
      final dir = await factory.getDatabasesPath();
      path = '$dir/$databaseFileName';
    }

    if (path != inMemoryDatabasePath) {
      await File(path).parent.create(recursive: true);
    }

    _database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: currentSchemaVersion,
        onCreate: onCreateDatabase,
        onUpgrade: onUpgradeDatabase,
      ),
    );

    return _database!;
  }

  static Future<void> onCreateDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS skill_states (
        id TEXT PRIMARY KEY,
        is_enabled INTEGER NOT NULL
      );
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS imported_skills (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        payload TEXT NOT NULL,
        source_url TEXT,
        imported_at INTEGER NOT NULL
      );
    ''');
  }

  static Future<void> onUpgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS imported_skills (
          id TEXT PRIMARY KEY,
          name TEXT NOT NULL,
          payload TEXT NOT NULL,
          source_url TEXT,
          imported_at INTEGER NOT NULL
        );
      ''');
    }
  }

  @override
  Future<List<Skill>> loadImportedSkills() async {
    final db = await database;
    final rows = await db.query(importedTableName, orderBy: 'imported_at ASC');
    final skills = <Skill>[];
    for (final row in rows) {
      try {
        final raw = row['payload'] as String;
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        skills.add(Skill.fromJson(decoded));
      } catch (_) {
        continue;
      }
    }
    return skills;
  }

  @override
  Future<void> saveImportedSkill(Skill skill, {String? sourceUrl}) async {
    final db = await database;
    await db.insert(importedTableName, {
      'id': skill.id,
      'name': skill.name,
      'payload': jsonEncode(skill.toJson()),
      'source_url': sourceUrl,
      'imported_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteImportedSkill(String skillId) async {
    final db = await database;
    await db.delete(importedTableName, where: 'id = ?', whereArgs: [skillId]);
  }

  @override
  Future<Map<String, bool>> loadSkillStates() async {
    final db = await database;
    final rows = await db.query(statesTableName);
    final states = <String, bool>{};
    for (final row in rows) {
      final id = row['id'];
      if (id is! String || id.isEmpty) {
        continue;
      }
      states[id] = (row['is_enabled'] as int? ?? 1) != 0;
    }
    return states;
  }

  @override
  Future<void> saveSkillState(String skillId, bool isEnabled) async {
    final db = await database;
    await db.insert(statesTableName, {
      'id': skillId,
      'is_enabled': isEnabled ? 1 : 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }
}
