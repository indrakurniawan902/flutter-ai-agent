import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/memory_item.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';

@LazySingleton(as: LocalMemoryServiceBase)
class LocalMemoryService implements LocalMemoryServiceBase {
  static const int currentSchemaVersion = 2;
  static const String databaseFileName = 'flames_memory.db';

  Database? _database;
  bool? _ftsSupported;
  final DatabaseFactory? _databaseFactory;
  final String? _databasePath;

  LocalMemoryService({
    Database? database,
    DatabaseFactory? databaseFactory,
    String? databasePath,
  })  : _database = database,
        _databaseFactory = databaseFactory,
        _databasePath = databasePath;

  @factoryMethod
  factory LocalMemoryService.create() => LocalMemoryService();

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

    _database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: currentSchemaVersion,
        onCreate: onCreateDatabase,
        onUpgrade: onUpgradeDatabase,
      ),
    );
    await _probeFtsSupport(_database!);

    return _database!;
  }

  Future<bool> _probeFtsSupport(Database db) async {
    final known = _ftsSupported;
    if (known != null) {
      return known;
    }
    try {
      await db.execute(
          'CREATE VIRTUAL TABLE IF NOT EXISTS temp.fts5_probe USING fts5(x)');
      await db.execute('DROP TABLE IF EXISTS temp.fts5_probe');
      _ftsSupported = true;
    } catch (_) {
      _ftsSupported = false;
    }
    return _ftsSupported!;
  }

  static Future<void> onCreateDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS memories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        key TEXT NOT NULL UNIQUE,
        content TEXT NOT NULL,
        tags TEXT NOT NULL DEFAULT '',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    try {
      await db.execute('''
        CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts USING fts5(
          key,
          content,
          tags,
          content='memories',
          content_rowid='id'
        );
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS memories_ai AFTER INSERT ON memories BEGIN
          INSERT INTO memories_fts(rowid, key, content, tags) VALUES (new.id, new.key, new.content, new.tags);
        END;
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS memories_ad AFTER DELETE ON memories BEGIN
          INSERT INTO memories_fts(memories_fts, rowid, key, content, tags) VALUES ('delete', old.id, old.key, old.content, old.tags);
        END;
      ''');

      await db.execute('''
        CREATE TRIGGER IF NOT EXISTS memories_au AFTER UPDATE ON memories BEGIN
          INSERT INTO memories_fts(memories_fts, rowid, key, content, tags) VALUES ('delete', old.id, old.key, old.content, old.tags);
          INSERT INTO memories_fts(rowid, key, content, tags) VALUES (new.id, new.key, new.content, new.tags);
        END;
      ''');
    } catch (_) {
      // FTS5 unavailable on this platform SQLite; skip FTS objects.
      // Searches degrade to the LIKE fallback path.
    }

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_memories_key ON memories(key);');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_memories_updated_at ON memories(updated_at);');
  }

  static Future<void> onUpgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_memories_key ON memories(key);');
      await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_memories_updated_at ON memories(updated_at);');
    }
  }

  @override
  Future<Either<Failure, MemoryItem>> saveMemory(
    String key,
    String content, [
    List<String> tags = const [],
  ]) async {
    try {
      final db = await database;
      final cleanKey = key.trim();
      final cleanContent = content.trim();

      if (cleanKey.isEmpty) {
        return const Left(StorageFailure('Memory key cannot be empty.'));
      }

      final now = DateTime.now().millisecondsSinceEpoch;
      final tagsStr = tags
          .map((t) => t.trim())
          .where((t) => t.isNotEmpty)
          .join(',');

      final existing = await db.query(
        'memories',
        where: 'key = ?',
        whereArgs: [cleanKey],
        limit: 1,
      );

      final MemoryItem item;
      if (existing.isNotEmpty) {
        final existingId = (existing.first['id'] as num).toInt();
        await db.update(
          'memories',
          {
            'content': cleanContent,
            'tags': tagsStr,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [existingId],
        );

        final parsedTags = tagsStr.isEmpty
            ? <String>[]
            : tagsStr
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();

        item = MemoryItem(
          id: existingId,
          key: cleanKey,
          content: cleanContent,
          tags: parsedTags,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            (existing.first['created_at'] as num).toInt(),
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        );
      } else {
        final newId = await db.insert('memories', {
          'key': cleanKey,
          'content': cleanContent,
          'tags': tagsStr,
          'created_at': now,
          'updated_at': now,
        });

        final parsedTags = tagsStr.isEmpty
            ? <String>[]
            : tagsStr
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();

        item = MemoryItem(
          id: newId,
          key: cleanKey,
          content: cleanContent,
          tags: parsedTags,
          createdAt: DateTime.fromMillisecondsSinceEpoch(now),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(now),
        );
      }
      return Right(item);
    } catch (e) {
      developer.log(
        '[local_memory] memory_unavailable: ${_shortReason(e)}',
        name: 'LocalMemoryService',
      );
      return Left(StorageFailure('memory_unavailable'));
    }
  }

  @override
  Future<Either<Failure, List<MemoryItem>>> searchMemories(
    String query, [
    int limit = 5,
  ]) {
    return _searchMemoriesInternal(query, limit);
  }

  Future<Either<Failure, List<MemoryItem>>> _searchMemoriesInternal(
    String query,
    int limit, [
    void Function(String mode)? onMode,
  ]) async {
    try {
      final db = await database;
      final ftsSupported = await _probeFtsSupport(db);
      final sanitizedMatchQuery = _sanitizeFtsQuery(query);

      if (sanitizedMatchQuery.isEmpty) {
        onMode?.call(ftsSupported ? 'fts5' : 'like_fallback');
        return const Right([]);
      }

      final List<Map<String, Object?>> results;
      if (ftsSupported) {
        onMode?.call('fts5');
        results = await db.rawQuery(
          '''
          SELECT m.id, m.key, m.content, m.tags, m.created_at, m.updated_at, bm25(memories_fts) AS rank
          FROM memories_fts fts
          JOIN memories m ON m.id = fts.rowid
          WHERE memories_fts MATCH ?
          ORDER BY rank ASC
          LIMIT ?;
          ''',
          [sanitizedMatchQuery, limit <= 0 ? 5 : limit],
        );
      } else {
        onMode?.call('like_fallback');
        results = await _searchWithLike(db, query, limit);
      }

      final items = results.map((row) => MemoryItem.fromDbMap(row)).toList();
      return Right(items);
    } catch (e) {
      developer.log(
        '[local_memory] memory_unavailable: ${_shortReason(e)}',
        name: 'LocalMemoryService',
      );
      return Left(StorageFailure('memory_unavailable'));
    }
  }

  Future<List<Map<String, Object?>>> _searchWithLike(
    Database db,
    String query,
    int limit,
  ) async {
    final words = _extractWords(query);
    if (words.isEmpty) return const [];

    final conditions = <String>[];
    final args = <Object?>[];
    for (final word in words) {
      conditions.add('(key LIKE ? OR content LIKE ? OR tags LIKE ?)');
      args
        ..add('%$word%')
        ..add('%$word%')
        ..add('%$word%');
    }

    return db.query(
      'memories',
      where: conditions.join(' OR '),
      whereArgs: args,
      orderBy: 'updated_at DESC',
      limit: limit <= 0 ? 5 : limit,
    );
  }

  @override
  Future<Either<Failure, bool>> deleteMemory(int id) async {
    try {
      final db = await database;
      final count = await db.delete(
        'memories',
        where: 'id = ?',
        whereArgs: [id],
      );
      return Right(count > 0);
    } catch (e) {
      return Left(
        StorageFailure(
          FailureMessage.humanize(e, context: 'Failed to delete memory (id: $id)'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, bool>> deleteMemoryByKey(String key) async {
    try {
      final db = await database;
      final count = await db.delete(
        'memories',
        where: 'key = ?',
        whereArgs: [key.trim()],
      );
      return Right(count > 0);
    } catch (e) {
      return Left(
        StorageFailure(
          FailureMessage.humanize(
            e,
            context: 'Failed to delete memory (key: $key)',
          ),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, MemoryItem?>> getMemoryByKey(String key) async {
    try {
      final db = await database;
      final results = await db.query(
        'memories',
        where: 'key = ?',
        whereArgs: [key.trim()],
        limit: 1,
      );

      if (results.isEmpty) {
        return const Right(null);
      }
      return Right(MemoryItem.fromDbMap(results.first));
    } catch (e) {
      return Left(
        StorageFailure(
          FailureMessage.humanize(e, context: 'Failed to get memory by key ($key)'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, MemoryItem?>> getMemoryById(int id) async {
    try {
      final db = await database;
      final results = await db.query(
        'memories',
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (results.isEmpty) {
        return const Right(null);
      }
      return Right(MemoryItem.fromDbMap(results.first));
    } catch (e) {
      return Left(
        StorageFailure(
          FailureMessage.humanize(e, context: 'Failed to get memory by id ($id)'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, List<MemoryItem>>> getAllMemories({
    int limit = 100,
  }) async {
    try {
      final db = await database;
      final results = await db.query(
        'memories',
        orderBy: 'updated_at DESC',
        limit: limit <= 0 ? 100 : limit,
      );

      final items = results.map((row) => MemoryItem.fromDbMap(row)).toList();
      return Right(items);
    } catch (e) {
      developer.log(
        '[local_memory] memory_unavailable: ${_shortReason(e)}',
        name: 'LocalMemoryService',
      );
      return Left(StorageFailure('memory_unavailable'));
    }
  }

  @override
  Future<Either<Failure, int>> clearAllMemories() async {
    try {
      final db = await database;
      final count = await db.delete('memories');
      return Right(count);
    } catch (e) {
      return Left(
        StorageFailure(
          FailureMessage.humanize(e, context: 'Failed to clear memories'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, String>> saveMemoryFormattedJson(
    Map<String, dynamic> args,
  ) async {
    final key = args['key']?.toString() ?? '';
    final content = args['content']?.toString() ?? '';

    List<String> tags = [];
    if (args['tags'] is List) {
      tags = (args['tags'] as List).map((e) => e.toString().trim()).toList();
    } else if (args['tags'] is String &&
        args['tags'].toString().isNotEmpty) {
      tags = args['tags'].toString().split(',').map((e) => e.trim()).toList();
    }

    final result = await saveMemory(key, content, tags);
    return result.fold(
      (failure) {
        if (failure.message.startsWith('memory_unavailable')) {
          return Right(
            jsonEncode({
              'status': 'memory_unavailable',
              'reason': failure.message,
            }),
          );
        }
        return Left(failure);
      },
      (item) => Right(
        jsonEncode({
          'status': 'saved',
          'id': item.id,
          'key': item.key,
          'content': item.content,
          'tags': item.tags,
          'updated_at': item.updatedAt.toIso8601String(),
        }),
      ),
    );
  }

  @override
  Future<Either<Failure, String>> searchMemoriesFormattedJson(
    Map<String, dynamic> args,
  ) async {
    final query = args['query']?.toString() ?? '';
    final limit = (args['limit'] as num?)?.toInt() ?? 5;

    var modeUsed = 'fts5';
    final result = await _searchMemoriesInternal(
      query,
      limit,
      (mode) => modeUsed = mode,
    );
    return result.fold(
      (failure) => Right(
        jsonEncode({
          'status': 'memory_unavailable',
          'reason': failure.message,
        }),
      ),
      (items) => Right(
        jsonEncode({
          'query': query,
          'count': items.length,
          'search_mode': modeUsed,
          'memories': items.map((m) => m.toJson()).toList(),
        }),
      ),
    );
  }

  @override
  Future<Either<Failure, String>> deleteMemoryFormattedJson(
    Map<String, dynamic> args,
  ) async {
    final dynamic idVal = args['id'];
    final keyVal = args['key']?.toString();

    if (idVal != null) {
      final id = int.tryParse(idVal.toString());
      if (id != null) {
        final result = await deleteMemory(id);
        return result.fold(
          (failure) => Right(
            jsonEncode({
              'status': 'memory_unavailable',
              'reason': failure.message,
            }),
          ),
          (deleted) => Right(jsonEncode({
            'status': deleted ? 'deleted' : 'not_found',
            'deleted': deleted,
            'id': id,
          })),
        );
      }
    }

    if (keyVal != null && keyVal.trim().isNotEmpty) {
      final result = await deleteMemoryByKey(keyVal.trim());
      return result.fold(
        (failure) => Right(
          jsonEncode({
            'status': 'memory_unavailable',
            'reason': failure.message,
          }),
        ),
        (deleted) => Right(jsonEncode({
          'status': deleted ? 'deleted' : 'not_found',
          'deleted': deleted,
          'key': keyVal,
        })),
      );
    }

    return const Left(
        StorageFailure('Either id or key must be provided to delete memory.'));
  }

  @override
  Future<Either<Failure, String>> listMemoriesFormattedJson([
    Map<String, dynamic> args = const {},
  ]) async {
    final limit = (args['limit'] as num?)?.toInt() ?? 50;
    final result = await getAllMemories(limit: limit);
    return result.fold(
      (failure) => Right(
        jsonEncode({
          'status': 'memory_unavailable',
          'reason': failure.message,
        }),
      ),
      (items) => Right(
        jsonEncode({
          'count': items.length,
          'memories': items.map((m) => m.toJson()).toList(),
        }),
      ),
    );
  }

  List<String> _extractWords(String input) {
    final clean = input.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    if (clean.isEmpty) return const [];

    return clean
        .split(RegExp(r'\s+'))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty && w.length >= 2)
        .toList();
  }

  String _sanitizeFtsQuery(String input) {
    final words = _extractWords(input);
    if (words.isEmpty) return '';

    return words.map((w) => '$w*').join(' OR ');
  }

  String _shortReason(Object error) {
    final text = error.toString();
    final match =
        RegExp(r'DatabaseException\(([^)]*)\)').firstMatch(text);
    final cause = (match?.group(1) ?? text).trim();
    return cause.length > 160 ? cause.substring(0, 160) : cause;
  }
}
