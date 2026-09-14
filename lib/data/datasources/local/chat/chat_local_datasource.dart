import 'dart:convert';

import 'package:flutter_ai_agent/common/exception.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/session.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:injectable/injectable.dart';
import 'package:sqflite/sqflite.dart';

abstract class ChatLocalDatasource {
  Future<List<ChatMessage>> getMessages(String sessionId);
  Future<void> saveMessages(String sessionId, List<ChatMessage> messages);
  Future<void> clearMessages(String sessionId);

  Future<List<Session>> getSessions(String profileId);
  Future<Session> createSession(String profileId, String title);
  Future<Session?> getSession(int sessionId);
  Future<void> updateSessionTitle(int sessionId, String title);
  Future<void> deleteSession(int sessionId);
}

@LazySingleton(as: ChatLocalDatasource)
class ChatLocalDatasourceImpl implements ChatLocalDatasource {
  static const int currentSchemaVersion = 1;
  static const String databaseFileName = 'flames_chat.db';

  final FlutterSecureStorage _storage;
  final Database? _injectedDatabase;
  final DatabaseFactory? _databaseFactory;
  final String? _databasePath;

  Database? _database;

  ChatLocalDatasourceImpl({
    required FlutterSecureStorage storage,
    Database? database,
    DatabaseFactory? databaseFactory,
    String? databasePath,
  })  : _storage = storage,
        _injectedDatabase = database,
        _databaseFactory = databaseFactory,
        _databasePath = databasePath;

  @factoryMethod
  factory ChatLocalDatasourceImpl.create({
    required FlutterSecureStorage storage,
  }) =>
      ChatLocalDatasourceImpl(storage: storage);

  static String keyFor(String sessionId) => 'chat_history_$sessionId';

  Future<Database> get database async {
    final injected = _injectedDatabase;
    if (injected != null) return injected;
    if (_database != null && _database!.isOpen) return _database!;

    final factory = _databaseFactory ?? databaseFactory;
    final String path;
    final configuredPath = _databasePath;
    if (configuredPath != null) {
      path = configuredPath;
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

  static Future<void> onCreateDatabase(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sessions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        profile_id TEXT NOT NULL,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      );
    ''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sessions_profile '
      'ON sessions (profile_id, updated_at DESC);',
    );
  }

  static Future<void> onUpgradeDatabase(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 1) {
      await onCreateDatabase(db, newVersion);
    }
  }

  @override
  Future<List<ChatMessage>> getMessages(String sessionId) async {
    return _readMessages(keyFor(sessionId));
  }

  @override
  Future<void> saveMessages(
    String sessionId,
    List<ChatMessage> messages,
  ) async {
    try {
      final encoded = jsonEncode(messages.map((m) => m.toJson()).toList());
      await _storage.write(key: keyFor(sessionId), value: encoded);
    } catch (e) {
      throw CacheException(
        FailureMessage.humanize(e, context: 'Failed to save chat history'),
      );
    }
  }

  @override
  Future<void> clearMessages(String sessionId) async {
    try {
      await _storage.delete(key: keyFor(sessionId));
    } catch (e) {
      throw CacheException(
        FailureMessage.humanize(e, context: 'Failed to clear chat history'),
      );
    }
  }

  @override
  Future<List<Session>> getSessions(String profileId) async {
    try {
      final db = await database;
      final rows = await db.query(
        'sessions',
        where: 'profile_id = ?',
        whereArgs: [profileId],
        orderBy: 'updated_at DESC',
      );
      return rows.map(_sessionFromRow).toList();
    } catch (e) {
      throw CacheException(
        FailureMessage.humanize(e, context: 'Failed to load chat sessions'),
      );
    }
  }

  @override
  Future<Session> createSession(String profileId, String title) async {
    try {
      final db = await database;
      final now = DateTime.now().millisecondsSinceEpoch;
      final id = await db.insert('sessions', {
        'profile_id': profileId,
        'title': title,
        'created_at': now,
        'updated_at': now,
      });
      return Session(
        id: id,
        profileId: profileId,
        title: title,
        createdAt: now,
        updatedAt: now,
      );
    } catch (e) {
      throw CacheException(
        FailureMessage.humanize(e, context: 'Failed to create chat session'),
      );
    }
  }

  @override
  Future<Session?> getSession(int sessionId) async {
    try {
      final db = await database;
      final rows = await db.query(
        'sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return _sessionFromRow(rows.first);
    } catch (e) {
      throw CacheException(
        FailureMessage.humanize(e, context: 'Failed to load chat session'),
      );
    }
  }

  @override
  Future<void> updateSessionTitle(int sessionId, String title) async {
    try {
      final db = await database;
      await db.update(
        'sessions',
        {
          'title': title,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [sessionId],
      );
    } catch (e) {
      throw CacheException(
        FailureMessage.humanize(
          e,
          context: 'Failed to update chat session title',
        ),
      );
    }
  }

  @override
  Future<void> deleteSession(int sessionId) async {
    try {
      final db = await database;
      await db.delete(
        'sessions',
        where: 'id = ?',
        whereArgs: [sessionId],
      );
      await _storage.delete(key: keyFor(sessionId.toString()));
    } catch (e) {
      throw CacheException(
        FailureMessage.humanize(e, context: 'Failed to delete chat session'),
      );
    }
  }

  Future<List<ChatMessage>> _readMessages(String key) async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null || raw.trim().isEmpty) return [];
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) return [];
        return decoded.map((item) {
          if (item is Map<String, dynamic>) {
            return ChatMessage.fromJson(item);
          } else if (item is Map) {
            return ChatMessage.fromJson(Map<String, dynamic>.from(item));
          }
          throw const FormatException('Invalid item in chat history');
        }).toList();
      } catch (_) {
        return [];
      }
    } catch (_) {
      return [];
    }
  }

  static Session _sessionFromRow(Map<String, Object?> row) {
    return Session(
      id: (row['id'] as num).toInt(),
      profileId: row['profile_id'] as String,
      title: row['title'] as String,
      createdAt: (row['created_at'] as num).toInt(),
      updatedAt: (row['updated_at'] as num).toInt(),
    );
  }
}
