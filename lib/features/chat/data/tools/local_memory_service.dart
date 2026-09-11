import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/models/memory_item.dart';
import 'package:sqflite/sqflite.dart';

/// Abstract contract for local persistent memory store using SQLite FTS5.
abstract class LocalMemoryServiceBase {
  /// Saves or updates a memory item with [key], [content], and optional [tags].
  Future<Either<Failure, MemoryItem>> saveMemory(
    String key,
    String content, [
    List<String> tags = const [],
  ]);

  /// Searches stored memories matching [query] using FTS5 BM25 relevance ranking.
  Future<Either<Failure, List<MemoryItem>>> searchMemories(
    String query, [
    int limit = 5,
  ]);

  /// Deletes a stored memory item by integer [id].
  Future<Either<Failure, bool>> deleteMemory(int id);

  /// Deletes a stored memory item by its unique [key].
  Future<Either<Failure, bool>> deleteMemoryByKey(String key);

  /// Retrieves a stored memory item by unique [key].
  Future<Either<Failure, MemoryItem?>> getMemoryByKey(String key);

  /// Retrieves a stored memory item by integer [id].
  Future<Either<Failure, MemoryItem?>> getMemoryById(int id);

  /// Retrieves all memories up to [limit], ordered by updated_at descending.
  Future<Either<Failure, List<MemoryItem>>> getAllMemories({int limit = 100});

  /// Clears all stored memories. Returns number of rows deleted.
  Future<Either<Failure, int>> clearAllMemories();

  /// JSON-formatted helper for agent tool execution: save_memory.
  Future<Either<Failure, String>> saveMemoryFormattedJson(
    Map<String, dynamic> args,
  );

  /// JSON-formatted helper for agent tool execution: search_memories.
  Future<Either<Failure, String>> searchMemoriesFormattedJson(
    Map<String, dynamic> args,
  );

  /// JSON-formatted helper for agent tool execution: delete_memory.
  Future<Either<Failure, String>> deleteMemoryFormattedJson(
    Map<String, dynamic> args,
  );

  /// JSON-formatted helper for agent tool execution: list_memories.
  Future<Either<Failure, String>> listMemoriesFormattedJson([
    Map<String, dynamic> args,
  ]);
}

/// Implementation of [LocalMemoryServiceBase] backed by SQLite with FTS5 virtual table.
class LocalMemoryService implements LocalMemoryServiceBase {
  static const int currentSchemaVersion = 2;
  static const String databaseFileName = 'flames_memory.db';

  Database? _database;
  final DatabaseFactory? _databaseFactory;
  final String? _databasePath;

  LocalMemoryService({
    Database? database,
    DatabaseFactory? databaseFactory,
    String? databasePath,
  })  : _database = database,
        _databaseFactory = databaseFactory,
        _databasePath = databasePath;

  /// Returns active database connection, opening if needed.
  Future<Database> get database async {
    if (_database != null && _database!.isOpen) {
      return _database!;
    }

    final factory = _databaseFactory ?? databaseFactory;
    final String path;
    if (_databasePath != null) {
      path = _databasePath;
    } else {
      final dir = await getDatabasesPath();
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

    return _database!;
  }

  /// Schema initialization for version 1 and 2.
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

    await db.execute('CREATE INDEX IF NOT EXISTS idx_memories_key ON memories(key);');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_memories_updated_at ON memories(updated_at);');
  }

  /// Migration handler across schema versions.
  static Future<void> onUpgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 2) {
      await db.execute('CREATE INDEX IF NOT EXISTS idx_memories_key ON memories(key);');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_memories_updated_at ON memories(updated_at);');
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
      final tagsStr = tags.map((t) => t.trim()).where((t) => t.isNotEmpty).join(',');

      // Check if item exists for upsert
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
            : tagsStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

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
            : tagsStr.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

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
      return Left(StorageFailure('Failed to save memory ($key): $e'));
    }
  }

  @override
  Future<Either<Failure, List<MemoryItem>>> searchMemories(
    String query, [
    int limit = 5,
  ]) async {
    try {
      final db = await database;
      final sanitizedMatchQuery = _sanitizeFtsQuery(query);

      if (sanitizedMatchQuery.isEmpty) {
        return const Right([]);
      }

      final results = await db.rawQuery(
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

      final items = results.map((row) => MemoryItem.fromDbMap(row)).toList();
      return Right(items);
    } catch (e) {
      return Left(StorageFailure('Failed to search memories: $e'));
    }
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
      return Left(StorageFailure('Failed to delete memory (id: $id): $e'));
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
      return Left(StorageFailure('Failed to delete memory (key: $key): $e'));
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
      return Left(StorageFailure('Failed to get memory by key ($key): $e'));
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
      return Left(StorageFailure('Failed to get memory by id ($id): $e'));
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
      return Left(StorageFailure('Failed to list memories: $e'));
    }
  }

  @override
  Future<Either<Failure, int>> clearAllMemories() async {
    try {
      final db = await database;
      final count = await db.delete('memories');
      return Right(count);
    } catch (e) {
      return Left(StorageFailure('Failed to clear memories: $e'));
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
    } else if (args['tags'] is String && args['tags'].toString().isNotEmpty) {
      tags = args['tags'].toString().split(',').map((e) => e.trim()).toList();
    }

    final result = await saveMemory(key, content, tags);
    return result.fold(
      (failure) => Left(failure),
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

    final result = await searchMemories(query, limit);
    return result.fold(
      (failure) => Left(failure),
      (items) => Right(
        jsonEncode({
          'query': query,
          'count': items.length,
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
          (failure) => Left(failure),
          (deleted) => Right(jsonEncode({'status': deleted ? 'deleted' : 'not_found', 'deleted': deleted, 'id': id})),
        );
      }
    }

    if (keyVal != null && keyVal.trim().isNotEmpty) {
      final result = await deleteMemoryByKey(keyVal.trim());
      return result.fold(
        (failure) => Left(failure),
        (deleted) => Right(jsonEncode({'status': deleted ? 'deleted' : 'not_found', 'deleted': deleted, 'key': keyVal})),
      );
    }

    return const Left(StorageFailure('Either id or key must be provided to delete memory.'));
  }

  @override
  Future<Either<Failure, String>> listMemoriesFormattedJson([
    Map<String, dynamic> args = const {},
  ]) async {
    final limit = (args['limit'] as num?)?.toInt() ?? 50;
    final result = await getAllMemories(limit: limit);
    return result.fold(
      (failure) => Left(failure),
      (items) => Right(
        jsonEncode({
          'count': items.length,
          'memories': items.map((m) => m.toJson()).toList(),
        }),
      ),
    );
  }

  /// Sanitizes user input into valid FTS5 query terms.
  /// Splits into words, strips unsafe punctuation, and joins with OR prefix tokens.
  String _sanitizeFtsQuery(String input) {
    final clean = input.replaceAll(RegExp(r'[^\w\s]'), ' ').trim();
    if (clean.isEmpty) return '';

    final words = clean
        .split(RegExp(r'\s+'))
        .map((w) => w.trim())
        .where((w) => w.isNotEmpty && w.length >= 2)
        .toList();

    if (words.isEmpty) return '';

    // Join terms with OR and prefix wildcards: term1* OR term2*
    return words.map((w) => '$w*').join(' OR ');
  }
}
