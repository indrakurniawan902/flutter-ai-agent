import 'dart:convert';
import 'dart:io';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/memory_item.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late LocalMemoryService service;

  setUpAll(() {
    sqfliteFfiInit();
  });

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: LocalMemoryService.currentSchemaVersion,
        onCreate: LocalMemoryService.onCreateDatabase,
        onUpgrade: LocalMemoryService.onUpgradeDatabase,
      ),
    );
    service = LocalMemoryService(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('LocalMemoryService.create', () {
    test('factory creates instance implementing base contract', () {
      expect(LocalMemoryService.create(), isA<LocalMemoryServiceBase>());
    });

    test('database getter returns open injected database', () async {
      final current = await service.database;
      expect(current.isOpen, isTrue);
    });

    test('database getter opens via factory and path when needed', () async {
      final lazy = LocalMemoryService(
        databaseFactory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final opened = await lazy.database;
      expect(opened.isOpen, isTrue);
      await opened.close();
    });
  });

  group('saveMemory CRUD', () {
    test('inserts new memory and retrieves by id and key', () async {
      final result = await service.saveMemory(
        'user_name',
        'User name is Alex',
        ['profile', 'identity'],
      );
      expect(result.isRight(), isTrue);
      final saved = result.getOrElse(() => throw StateError('no item'));
      expect(saved.id, isNotNull);
      expect(saved.key, 'user_name');
      expect(saved.content, 'User name is Alex');
      expect(saved.tags, ['profile', 'identity']);

      final byKey = await service.getMemoryByKey('user_name');
      expect(byKey.isRight(), isTrue);
      byKey.fold(
        (_) => fail('should succeed'),
        (item) {
          expect(item, isNotNull);
          expect(item!.id, saved.id);
          expect(item.content, 'User name is Alex');
        },
      );

      final byId = await service.getMemoryById(saved.id!);
      expect(byId.isRight(), isTrue);
      byId.fold(
        (_) => fail('should succeed'),
        (item) {
          expect(item, isNotNull);
          expect(item!.key, 'user_name');
        },
      );
    });

    test('trims key content and cleans tags on insert', () async {
      final result = await service.saveMemory(
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

    test('upserts when key already exists without duplicating rows',
        () async {
      await service.saveMemory('user_location', 'Bandung, Indonesia', [
        'location',
      ]);
      final updated = await service.saveMemory(
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

      final all = await service.getAllMemories();
      all.fold(
        (_) => fail('should succeed'),
        (list) {
          expect(list.length, 1);
          expect(list.first.content, 'Jakarta, Indonesia');
        },
      );
    });

    test('returns StorageFailure for empty key', () async {
      final result = await service.saveMemory('   ', 'content');
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
      final result = await service.saveMemory('k', 'v');
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
          (await service.saveMemory('temp_key', 'temporary')).getOrElse(
        () => throw StateError('no item'),
      );
      final deleted = await service.deleteMemory(saved.id!);
      expect(deleted.isRight(), isTrue);
      expect(deleted.getOrElse(() => false), isTrue);

      final after = await service.getMemoryById(saved.id!);
      after.fold(
        (_) => fail('should succeed'),
        (item) => expect(item, isNull),
      );

      final again = await service.deleteMemory(saved.id!);
      expect(again.getOrElse(() => true), isFalse);
    });

    test('deleteMemoryByKey removes by key', () async {
      await service.saveMemory('key_to_delete', 'some content');
      final deleted = await service.deleteMemoryByKey('key_to_delete');
      expect(deleted.getOrElse(() => false), isTrue);

      final after = await service.getMemoryByKey('key_to_delete');
      after.fold(
        (_) => fail('should succeed'),
        (item) => expect(item, isNull),
      );
    });

    test('deleteMemoryByKey returns false for unknown key', () async {
      final result = await service.deleteMemoryByKey('no_such_key');
      expect(result.getOrElse(() => true), isFalse);
    });

    test('getMemoryByKey returns null for unknown key', () async {
      final result = await service.getMemoryByKey('missing');
      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => MemoryItem(
            key: 'x',
            content: 'x',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          )),
          isNull);
    });

    test('getMemoryById returns null for unknown id', () async {
      final result = await service.getMemoryById(999999);
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed'),
        (item) => expect(item, isNull),
      );
    });

    test('getAllMemories orders by updated_at descending', () async {
      await service.saveMemory('k1', 'c1');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      await service.saveMemory('k2', 'c2');
      final all = await service.getAllMemories();
      all.fold(
        (_) => fail('should succeed'),
        (list) {
          expect(list.length, 2);
          expect(list.first.key, 'k2');
        },
      );
    });

    test('getAllMemories falls back for non-positive limit', () async {
      await service.saveMemory('k1', 'c1');
      final result = await service.getAllMemories(limit: 0);
      expect(result.isRight(), isTrue);
    });

    test('clearAllMemories removes all rows and reports count', () async {
      await service.saveMemory('k1', 'c1');
      await service.saveMemory('k2', 'c2');
      await service.saveMemory('k3', 'c3');
      final cleared = await service.clearAllMemories();
      expect(cleared.getOrElse(() => -1), 3);

      final empty = await service.getAllMemories();
      empty.fold(
        (_) => fail('should succeed'),
        (list) => expect(list, isEmpty),
      );
    });

    test('read methods return StorageFailure when database closed', () async {
      await db.close();
      expect((await service.searchMemories('q')).isLeft(), isTrue);
      expect((await service.deleteMemory(1)).isLeft(), isTrue);
      expect((await service.deleteMemoryByKey('k')).isLeft(), isTrue);
      expect((await service.getMemoryByKey('k')).isLeft(), isTrue);
      expect((await service.getMemoryById(1)).isLeft(), isTrue);
      expect((await service.getAllMemories()).isLeft(), isTrue);
      expect((await service.clearAllMemories()).isLeft(), isTrue);
    });
  });

  group('FTS5 search with BM25 ranking', () {
    setUp(() async {
      await service.saveMemory(
        'user_profile',
        'Alex is a software engineer working with Flutter and Dart on mobile applications.',
        ['profile', 'engineering'],
      );
      await service.saveMemory(
        'favorite_editor',
        'Alex loves using Neovim and VS Code for writing Flutter and Dart code every day.',
        ['tools', 'preferences'],
      );
      await service.saveMemory(
        'pet_info',
        'Alex has a white cat named Snow who loves sleeping on laptops.',
        ['personal', 'pets'],
      );
      await service.saveMemory(
        'weekend_plan',
        'Going hiking in the mountains near Bandung this Saturday morning.',
        ['plans', 'outdoors'],
      );
    });

    test('retrieves matches ordered with relevance scores', () async {
      final result = await service.searchMemories('Flutter Dart', 5);
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
      final result = await service.searchMemories('engineering', 5);
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
          await service.searchMemories('nonexistentterm123', 5);
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed'),
        (matches) => expect(matches, isEmpty),
      );
    });

    test('respects limit parameter', () async {
      final result = await service.searchMemories('Alex', 2);
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed'),
        (matches) => expect(matches.length, 2),
      );
    });

    test('falls back to default limit for non-positive limit', () async {
      final result = await service.searchMemories('Alex', 0);
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed'),
        (matches) => expect(matches.length, 3),
      );
    });

    test('sanitizes punctuation safely', () async {
      final result =
          await service.searchMemories('cat? (Snow)! "*"', 5);
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
      final blank = await service.searchMemories('   ');
      expect(blank.isRight(), isTrue);
      expect(blank.getOrElse(() => <MemoryItem>[]), isEmpty);
      final punct = await service.searchMemories('?!...');
      expect(punct.isRight(), isTrue);
      expect(punct.getOrElse(() => <MemoryItem>[]), isEmpty);
      final short = await service.searchMemories('a I');
      expect(short.isRight(), isTrue);
      expect(short.getOrElse(() => <MemoryItem>[]), isEmpty);
    });
  });

  group('formatted JSON helpers', () {
    test('saveMemoryFormattedJson handles list tags', () async {
      final result = await service.saveMemoryFormattedJson({
        'key': 'bot_mission',
        'content': 'To assist the user proactively on device tasks.',
        'tags': ['mission', 'ai'],
      });
      expect(result.isRight(), isTrue);
      final raw = result.getOrElse(() => '');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded['status'], 'saved');
      expect(decoded['key'], 'bot_mission');
      expect(decoded['tags'], ['mission', 'ai']);
      expect(decoded['id'], isNotNull);
    });

    test('saveMemoryFormattedJson handles comma string tags', () async {
      final result = await service.saveMemoryFormattedJson({
        'key': 'str_tags',
        'content': 'content here',
        'tags': 'a, b',
      });
      expect(result.isRight(), isTrue);
      final decoded =
          jsonDecode(result.getOrElse(() => '')) as Map<String, dynamic>;
      expect(decoded['tags'], ['a', 'b']);
    });

    test('saveMemoryFormattedJson defaults missing tags', () async {
      final result = await service.saveMemoryFormattedJson({
        'key': 'no_tags',
        'content': 'content here',
      });
      expect(result.isRight(), isTrue);
    });

    test('saveMemoryFormattedJson surfaces validation failure', () async {
      final result = await service.saveMemoryFormattedJson({
        'key': '   ',
        'content': 'content',
      });
      expect(result.isLeft(), isTrue);
    });

    test('searchMemoriesFormattedJson returns query envelope', () async {
      await service.saveMemory('bot_mission', 'To assist proactively.');
      final result = await service.searchMemoriesFormattedJson({
        'query': 'proactively mission',
        'limit': 5,
      });
      expect(result.isRight(), isTrue);
      final decoded =
          jsonDecode(result.getOrElse(() => '')) as Map<String, dynamic>;
      expect(decoded['query'], 'proactively mission');
      expect(decoded['count'], 1);
      expect((decoded['memories'] as List).length, 1);
    });

    test('searchMemoriesFormattedJson defaults limit', () async {
      await service.saveMemory('k1', 'hello world memory');
      final result = await service.searchMemoriesFormattedJson({
        'query': 'hello',
      });
      expect(result.isRight(), isTrue);
    });

    test('deleteMemoryFormattedJson deletes by id', () async {
      final saved = (await service.saveMemory('item_a', 'content a'))
          .getOrElse(() => throw StateError('no item'));
      final result = await service.deleteMemoryFormattedJson({
        'id': saved.id,
      });
      expect(result.isRight(), isTrue);
      final decoded =
          jsonDecode(result.getOrElse(() => '')) as Map<String, dynamic>;
      expect(decoded['deleted'], isTrue);
      expect(decoded['status'], 'deleted');
    });

    test('deleteMemoryFormattedJson reports not_found id', () async {
      final result = await service.deleteMemoryFormattedJson({'id': 999999});
      expect(result.isRight(), isTrue);
      final decoded =
          jsonDecode(result.getOrElse(() => '')) as Map<String, dynamic>;
      expect(decoded['deleted'], isFalse);
      expect(decoded['status'], 'not_found');
    });

    test('deleteMemoryFormattedJson deletes by key', () async {
      await service.saveMemory('item_b', 'content b');
      final result = await service.deleteMemoryFormattedJson({
        'key': 'item_b',
      });
      expect(result.isRight(), isTrue);
      final decoded =
          jsonDecode(result.getOrElse(() => '')) as Map<String, dynamic>;
      expect(decoded['deleted'], isTrue);
    });

    test('deleteMemoryFormattedJson falls back to key for invalid id',
        () async {
      await service.saveMemory('item_c', 'content c');
      final result = await service.deleteMemoryFormattedJson({
        'id': 'not-a-number',
        'key': 'item_c',
      });
      expect(result.isRight(), isTrue);
      final decoded =
          jsonDecode(result.getOrElse(() => '')) as Map<String, dynamic>;
      expect(decoded['deleted'], isTrue);
    });

    test('deleteMemoryFormattedJson requires id or key', () async {
      final result = await service.deleteMemoryFormattedJson({});
      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<StorageFailure>()),
        (_) => fail('expected Left'),
      );
    });

    test('listMemoriesFormattedJson returns count envelope', () async {
      await service.saveMemory('item_a', 'content a');
      await service.saveMemory('item_b', 'content b');
      final result = await service.listMemoriesFormattedJson({'limit': 10});
      expect(result.isRight(), isTrue);
      final decoded =
          jsonDecode(result.getOrElse(() => '')) as Map<String, dynamic>;
      expect(decoded['count'], 2);
      expect((decoded['memories'] as List).length, 2);
    });

    test('listMemoriesFormattedJson defaults args', () async {
      await service.saveMemory('k1', 'c1');
      final result = await service.listMemoriesFormattedJson();
      expect(result.isRight(), isTrue);
    });
  });

  group('schema migrations', () {
    test('onUpgradeDatabase migrates v1 to v2 preserving rows', () async {
      final tempPath =
          '${Directory.systemTemp.path}/test_mem_mig_${DateTime.now().microsecondsSinceEpoch}.db';
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
          onCreate: LocalMemoryService.onCreateDatabase,
          onUpgrade: LocalMemoryService.onUpgradeDatabase,
        ),
      );
      final upgraded = LocalMemoryService(database: upgradedDb);
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
      await LocalMemoryService.onUpgradeDatabase(db, 2, 2);
      final result = await service.saveMemory('still_works', 'yes');
      expect(result.isRight(), isTrue);
    });
  });

  group('FTS5 unavailability resilience', () {
    test('degrades to LIKE fallback when FTS5 module is missing', () async {
      final svc = LocalMemoryService(
        databaseFactory: _NoFtsFactory(databaseFactoryFfi),
        databasePath: inMemoryDatabasePath,
      );

      final save1 = await svc.saveMemory('needle_note', 'the needle is here');
      expect(save1.isRight(), isTrue);
      final save2 = await svc.saveMemory('plain_note', 'nothing special');
      expect(save2.isRight(), isTrue);

      final result = await svc.searchMemories('needle');
      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('should succeed via LIKE fallback'),
        (matches) {
          expect(matches.length, 1);
          expect(matches.first.key, 'needle_note');
        },
      );

      final json = await svc.searchMemoriesFormattedJson({'query': 'needle'});
      expect(json.isRight(), isTrue);
      final decoded =
          jsonDecode(json.getOrElse(() => '')) as Map<String, dynamic>;
      expect(decoded['search_mode'], 'like_fallback');
      expect(decoded['count'], 1);

      final svcDb = await svc.database;
      await svcDb.close();
    });

    test('reports fts5 search mode on FTS5-capable database', () async {
      await service.saveMemory('mode_probe', 'mode probe content');
      final json = await service.searchMemoriesFormattedJson({
        'query': 'probe',
      });
      expect(json.isRight(), isTrue);
      final decoded =
          jsonDecode(json.getOrElse(() => '')) as Map<String, dynamic>;
      expect(decoded['search_mode'], 'fts5');
    });

    test(
        'onCreateDatabase still creates base schema when FTS5 is unsupported',
        () async {
      final factory = _NoFtsFactory(databaseFactoryFfi);
      final opened = await factory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: LocalMemoryService.currentSchemaVersion,
          onCreate: LocalMemoryService.onCreateDatabase,
        ),
      );
      final svc = LocalMemoryService(database: opened);
      final result = await svc.saveMemory('base_only', 'base schema works');
      expect(result.isRight(), isTrue);
      final all = await svc.getAllMemories();
      expect(all.getOrElse(() => []).length, 1);
      await opened.close();
    });

    test('unavailable open surfaces structured memory_unavailable failure',
        () async {
      final svc = LocalMemoryService(
        databaseFactory: _BrokenFactory(),
        databasePath: inMemoryDatabasePath,
      );

      final saved = await svc.saveMemory('k', 'v');
      expect(saved.isLeft(), isTrue);
      saved.fold(
        (failure) {
          expect(failure, isA<StorageFailure>());
          expect(failure.message, 'memory_unavailable');
          expect(failure.message, isNot(contains('Exception')));
        },
        (_) => fail('expected Left'),
      );

      final listed = await svc.getAllMemories();
      expect(listed.isLeft(), isTrue);
      listed.fold(
        (failure) => expect(failure.message, 'memory_unavailable'),
        (_) => fail('expected Left'),
      );

      final json = await svc.searchMemoriesFormattedJson({'query': 'x'});
      expect(json.isRight(), isTrue);
      final decoded =
          jsonDecode(json.getOrElse(() => '')) as Map<String, dynamic>;
      expect(decoded['status'], 'memory_unavailable');
      expect(decoded['reason'], isNotEmpty);
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
