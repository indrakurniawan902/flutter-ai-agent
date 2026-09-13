import 'dart:io';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/local/memory/sqlite_memory_datasource.dart';
import 'package:flutter_ai_agent/domain/entities/chat/memory_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late SqliteMemoryDatasource datasource;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: SqliteMemoryDatasource.currentSchemaVersion,
        onCreate: SqliteMemoryDatasource.onCreateDatabase,
        onUpgrade: SqliteMemoryDatasource.onUpgradeDatabase,
      ),
    );
    datasource = SqliteMemoryDatasource(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('SqliteMemoryDatasource initialization', () {
    test('factory creates instance', () {
      expect(SqliteMemoryDatasource.create(), isA<SqliteMemoryDatasource>());
    });

    test('database getter returns open injected database', () async {
      final current = await datasource.database;
      expect(current.isOpen, isTrue);
    });

    test('database getter opens via factory and path', () async {
      final ds = SqliteMemoryDatasource(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final opened = await ds.database;
      expect(opened.isOpen, isTrue);
      await ds.close();
    });

    test('creates parent directories recursively before opening', () async {
      final random = DateTime.now().microsecondsSinceEpoch;
      final tempDir = Directory('${Directory.systemTemp.path}/test_db_dir_$random/sub');
      final dbPath = '${tempDir.path}/nested_flames_memory.db';

      expect(await tempDir.exists(), isFalse);

      final ds = SqliteMemoryDatasource(
        databaseFactory: databaseFactoryFfi,
        databasePath: dbPath,
      );

      final opened = await ds.database;
      expect(opened.isOpen, isTrue);
      expect(await tempDir.exists(), isTrue);

      final saveRes = await ds.saveMemory('cold_key', 'cold start content');
      expect(saveRes.isRight(), isTrue);

      await ds.close();

      final file = File(dbPath);
      if (await file.exists()) {
        await file.delete();
      }
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
  });

  group('saveMemory CRUD', () {
    test('inserts new memory and retrieves by id and key', () async {
      final result = await datasource.saveMemory(
        'user_name',
        'User name is Indra',
        ['profile', 'identity'],
      );
      expect(result.isRight(), isTrue);
      final saved = result.getOrElse(() => throw StateError('no item'));
      expect(saved.id, isNotNull);
      expect(saved.key, 'user_name');
      expect(saved.content, 'User name is Indra');
      expect(saved.tags, ['profile', 'identity']);

      final byKey = await datasource.getMemoryByKey('user_name');
      expect(byKey.isRight(), isTrue);
      byKey.fold(
        (_) => fail('should succeed'),
        (item) {
          expect(item, isNotNull);
          expect(item!.id, saved.id);
          expect(item.content, 'User name is Indra');
        },
      );

      final byId = await datasource.getMemoryById(saved.id!);
      expect(byId.isRight(), isTrue);
      byId.fold(
        (_) => fail('should succeed'),
        (item) {
          expect(item, isNotNull);
          expect(item!.key, 'user_name');
        },
      );
    });

    test('trims key and content and filters empty tags', () async {
      final result = await datasource.saveMemory(
        '  spaced_key  ',
        '  spaced content  ',
        [' a ', '', '  ', 'b'],
      );
      expect(result.isRight(), isTrue);
      final saved = result.getOrElse(() => throw StateError('no item'));
      expect(saved.key, 'spaced_key');
      expect(saved.content, 'spaced content');
      expect(saved.tags, ['a', 'b']);
    });

    test('upserts when key already exists without duplicating rows', () async {
      await datasource.saveMemory('user_location', 'Bandung, Indonesia', [
        'location',
      ]);
      final updated = await datasource.saveMemory(
        'user_location',
        'Jakarta, Indonesia',
        ['location', 'travel'],
      );
      expect(updated.isRight(), isTrue);
      updated.fold(
        (_) => fail('should succeed'),
        (item) {
          expect(item.content, 'Jakarta, Indonesia');
          expect(item.tags, ['location', 'travel']);
        },
      );

      final all = await datasource.getAllMemories();
      all.fold(
        (_) => fail('should succeed'),
        (list) {
          expect(list.length, 1);
          expect(list.first.content, 'Jakarta, Indonesia');
        },
      );
    });

    test('returns StorageFailure for empty key', () async {
      final result = await datasource.saveMemory('   ', 'content');
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<StorageFailure>());
          expect(failure.message, contains('cannot be empty'));
        },
        (_) => fail('expected Left'),
      );
    });

    test('returns StorageFailure when database is closed', () async {
      await db.close();
      final result = await datasource.saveMemory('k', 'v');
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<StorageFailure>()),
        (_) => fail('expected Left'),
      );
    });
  });

  group('delete and get', () {
    test('deleteMemory removes by id and reports missing ids', () async {
      final saved =
          (await datasource.saveMemory('temp_key', 'temporary')).getOrElse(
        () => throw StateError('no item'),
      );
      final deleted = await datasource.deleteMemory(saved.id!);
      expect(deleted.isRight(), isTrue);
      expect(deleted.getOrElse(() => false), isTrue);

      final after = await datasource.getMemoryById(saved.id!);
      after.fold(
        (_) => fail('should succeed'),
        (item) => expect(item, isNull),
      );

      final again = await datasource.deleteMemory(saved.id!);
      expect(again.getOrElse(() => true), isFalse);
    });

    test('deleteMemoryByKey removes by key', () async {
      await datasource.saveMemory('key_to_delete', 'some content');
      final deleted = await datasource.deleteMemoryByKey('key_to_delete');
      expect(deleted.getOrElse(() => false), isTrue);

      final after = await datasource.getMemoryByKey('key_to_delete');
      after.fold(
        (_) => fail('should succeed'),
        (item) => expect(item, isNull),
      );
    });

    test('deleteMemoryByKey returns false for unknown key', () async {
      final result = await datasource.deleteMemoryByKey('no_such_key');
      expect(result.getOrElse(() => true), isFalse);
    });

    test('getMemoryByKey returns null for unknown key', () async {
      final result = await datasource.getMemoryByKey('missing');
      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => MemoryItem(
            key: 'x',
            content: 'x',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          )), isNull);
    });

    test('getMemoryById returns null for unknown id', () async {
      final result = await datasource.getMemoryById(999999);
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed'),
        (item) => expect(item, isNull),
      );
    });

    test('getAllMemories orders by updated_at descending', () async {
      await datasource.saveMemory('k1', 'c1');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await datasource.saveMemory('k2', 'c2');
      final all = await datasource.getAllMemories();
      all.fold(
        (_) => fail('should succeed'),
        (list) {
          expect(list.length, 2);
          expect(list.first.key, 'k2');
        },
      );
    });

    test('getAllMemories handles non-positive limit', () async {
      await datasource.saveMemory('k1', 'c1');
      final result = await datasource.getAllMemories(limit: 0);
      expect(result.isRight(), isTrue);
    });

    test('clearAllMemories removes all rows and reports count', () async {
      await datasource.saveMemory('k1', 'c1');
      await datasource.saveMemory('k2', 'c2');
      await datasource.saveMemory('k3', 'c3');
      final cleared = await datasource.clearAllMemories();
      expect(cleared.getOrElse(() => -1), 3);

      final empty = await datasource.getAllMemories();
      empty.fold(
        (_) => fail('should succeed'),
        (list) => expect(list, isEmpty),
      );
    });

    test('methods return StorageFailure when database closed', () async {
      await db.close();
      expect((await datasource.searchMemories('q')).isLeft(), isTrue);
      expect((await datasource.deleteMemory(1)).isLeft(), isTrue);
      expect((await datasource.deleteMemoryByKey('k')).isLeft(), isTrue);
      expect((await datasource.getMemoryByKey('k')).isLeft(), isTrue);
      expect((await datasource.getMemoryById(1)).isLeft(), isTrue);
      expect((await datasource.getAllMemories()).isLeft(), isTrue);
      expect((await datasource.clearAllMemories()).isLeft(), isTrue);
    });
  });

  group('FTS5 search with BM25 ranking', () {
    setUp(() async {
      await datasource.saveMemory(
        'user_profile',
        'Indra is a software engineer working with Flutter and Dart on mobile applications.',
        ['profile', 'engineering'],
      );
      await datasource.saveMemory(
        'favorite_editor',
        'Indra loves using Neovim and VS Code for writing Flutter and Dart code every day.',
        ['tools', 'preferences'],
      );
      await datasource.saveMemory(
        'pet_info',
        'Indra has a white cat named Snow who loves sleeping on laptops.',
        ['personal', 'pets'],
      );
      await datasource.saveMemory(
        'weekend_plan',
        'Going hiking in the mountains near Bandung this Saturday morning.',
        ['plans', 'outdoors'],
      );
    });

    test('retrieves matches ordered with relevance scores', () async {
      final result = await datasource.searchMemories('Flutter Dart', 5);
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed'),
        (matches) {
          expect(matches.length, 2);
          for (final m in matches) {
            expect(m.score, isNotNull);
            expect(m.content, contains('Flutter'));
          }
        },
      );
    });

    test('matches keywords in tags', () async {
      final result = await datasource.searchMemories('engineering', 5);
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed'),
        (matches) {
          expect(matches.length, 1);
          expect(matches.first.key, 'user_profile');
        },
      );
    });

    test('returns empty list for no matches', () async {
      final result =
          await datasource.searchMemories('nonexistentterm123', 5);
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed'),
        (matches) => expect(matches, isEmpty),
      );
    });

    test('respects limit parameter', () async {
      final result = await datasource.searchMemories('Indra', 2);
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed'),
        (matches) => expect(matches.length, 2),
      );
    });

    test('falls back to default limit for non-positive limit', () async {
      final result = await datasource.searchMemories('Indra', 0);
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed'),
        (matches) => expect(matches.length, 3),
      );
    });

    test('sanitizes punctuation safely', () async {
      final result =
          await datasource.searchMemories('cat? (Snow)! "*"', 5);
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed'),
        (matches) {
          expect(matches.length, 1);
          expect(matches.first.key, 'pet_info');
        },
      );
    });

    test('returns empty for blank or too-short queries', () async {
      final blank = await datasource.searchMemories('   ');
      expect(blank.isRight(), isTrue);
      expect(blank.getOrElse(() => <MemoryItem>[]), isEmpty);
      final punct = await datasource.searchMemories('?!...');
      expect(punct.isRight(), isTrue);
      expect(punct.getOrElse(() => <MemoryItem>[]), isEmpty);
      final short = await datasource.searchMemories('a I');
      expect(short.isRight(), isTrue);
      expect(short.getOrElse(() => <MemoryItem>[]), isEmpty);
    });
  });

  group('FTS5 unavailability resilience', () {
    test('degrades to LIKE fallback when FTS5 module is missing', () async {
      final ds = SqliteMemoryDatasource(
        databaseFactory: _NoFtsFactory(databaseFactoryFfi),
        databasePath: inMemoryDatabasePath,
      );

      final save1 = await ds.saveMemory('needle_note', 'the needle is here');
      expect(save1.isRight(), isTrue);
      final save2 = await ds.saveMemory('plain_note', 'nothing special');
      expect(save2.isRight(), isTrue);

      final result = await ds.searchMemories('needle');
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed via LIKE fallback'),
        (matches) {
          expect(matches.length, 1);
          expect(matches.first.key, 'needle_note');
        },
      );

      await ds.close();
    });

    test('unavailable open surfaces structured memory_unavailable failure',
        () async {
      final ds = SqliteMemoryDatasource(
        databaseFactory: _BrokenFactory(),
        databasePath: inMemoryDatabasePath,
      );

      final saved = await ds.saveMemory('k', 'v');
      expect(saved.isLeft(), isTrue);
      saved.fold(
        (failure) {
          expect(failure, isA<StorageFailure>());
          expect(failure.message, startsWith('memory_unavailable:'));
        },
        (_) => fail('expected Left'),
      );

      final listed = await ds.getAllMemories();
      expect(listed.isLeft(), isTrue);
      listed.fold(
        (failure) =>
            expect(failure.message, startsWith('memory_unavailable:')),
        (_) => fail('expected Left'),
      );
    });
  });

  group('schema migrations', () {
    test('onUpgradeDatabase migrates v1 to v2 preserving rows', () async {
      final tempPath =
          '${Directory.systemTemp.path}/test_ds_mig_${DateTime.now().microsecondsSinceEpoch}.db';
      final v1Db = await databaseFactoryFfi.openDatabase(
        tempPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE memories (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                key TEXT NOT NULL UNIQUE,
                content TEXT NOT NULL,
                tags TEXT NOT NULL DEFAULT '',
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
              );
            ''');
            await db.execute('''
              CREATE VIRTUAL TABLE memories_fts USING fts5(
                key,
                content,
                tags,
                content='memories',
                content_rowid='id'
              );
            ''');
          },
        ),
      );
      final now = DateTime.now().millisecondsSinceEpoch;
      await v1Db.insert('memories', {
        'key': 'v1_test_key',
        'content': 'Data created in schema v1',
        'tags': 'v1,legacy',
        'created_at': now,
        'updated_at': now,
      });
      await v1Db.close();

      final upgradedDb = await databaseFactoryFfi.openDatabase(
        tempPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: SqliteMemoryDatasource.onCreateDatabase,
          onUpgrade: SqliteMemoryDatasource.onUpgradeDatabase,
        ),
      );
      final upgraded = SqliteMemoryDatasource(database: upgradedDb);
      final found = await upgraded.getMemoryByKey('v1_test_key');
      expect(found.isRight(), isTrue);
      found.fold(
        (_) => fail('should succeed'),
        (item) {
          expect(item, isNotNull);
          expect(item!.content, 'Data created in schema v1');
        },
      );
      await upgradedDb.close();
      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
      }
    });

    test('onUpgradeDatabase is no-op when already at v2', () async {
      await SqliteMemoryDatasource.onUpgradeDatabase(db, 2, 2);
      final result = await datasource.saveMemory('still_works', 'yes');
      expect(result.isRight(), isTrue);
    });
  });
}

class _TestDatabaseException extends DatabaseException {
  _TestDatabaseException(super.message);
  @override
  int? getResultCode() => null;
  @override
  Object? get result => null;
}

class _NoFtsDatabase implements Database {
  _NoFtsDatabase(this._inner);

  final Database _inner;

  bool _isFtsSql(String sql) {
    final upper = sql.toUpperCase();
    return upper.contains('USING FTS5') || upper.contains('MEMORIES_FTS');
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    if (_isFtsSql(sql)) {
      throw _TestDatabaseException('no such module: fts5');
    }
    await _inner.execute(sql, arguments);
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) =>
      _inner.query(
        table,
        distinct: distinct,
        columns: columns,
        where: where,
        whereArgs: whereArgs,
        groupBy: groupBy,
        having: having,
        orderBy: orderBy,
        limit: limit,
        offset: offset,
      );

  @override
  Future<int> insert(String table, Map<String, Object?> values,
          {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) =>
      _inner.insert(table, values,
          nullColumnHack: nullColumnHack,
          conflictAlgorithm: conflictAlgorithm);

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) =>
      _inner.update(
        table,
        values,
        where: where,
        whereArgs: whereArgs,
        conflictAlgorithm: conflictAlgorithm,
      );

  @override
  Future<int> delete(String table,
          {String? where, List<Object?>? whereArgs}) =>
      _inner.delete(table, where: where, whereArgs: whereArgs);

  @override
  bool get isOpen => _inner.isOpen;

  @override
  Future<void> close() => _inner.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoFtsFactory implements DatabaseFactory {
  _NoFtsFactory(this._inner);

  final DatabaseFactory _inner;

  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) =>
      _inner
          .openDatabase(path, options: options)
          .then((db) => _NoFtsDatabase(db));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BrokenFactory implements DatabaseFactory {
  @override
  Future<Database> openDatabase(String path, {OpenDatabaseOptions? options}) {
    throw _TestDatabaseException('unable to open database file');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
