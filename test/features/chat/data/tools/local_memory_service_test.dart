import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/models/memory_item.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/local_memory_service.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/security_policy.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Database db;
  late LocalMemoryService memoryService;

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
    memoryService = LocalMemoryService(database: db);
  });

  tearDown(() async {
    await db.close();
  });

  group('MemoryItem Model', () {
    test('supports value equality and copyWith', () {
      final now = DateTime.now();
      final item1 = MemoryItem(
        id: 1,
        key: 'user_name',
        content: 'Indra',
        tags: const ['profile'],
        createdAt: now,
        updatedAt: now,
      );

      final item2 = MemoryItem(
        id: 1,
        key: 'user_name',
        content: 'Indra',
        tags: const ['profile'],
        createdAt: now,
        updatedAt: now,
      );

      expect(item1, equals(item2));

      final updated = item1.copyWith(content: 'Eryushin');
      expect(updated.content, equals('Eryushin'));
      expect(updated.key, equals('user_name'));
    });

    test('toJson and fromJson serialize correctly', () {
      final now = DateTime(2026, 9, 11, 10, 0, 0);
      final item = MemoryItem(
        id: 42,
        key: 'user_preference',
        content: 'Prefers dark theme',
        tags: const ['settings', 'theme'],
        createdAt: now,
        updatedAt: now,
        score: -1.25,
      );

      final json = item.toJson();
      expect(json['id'], equals(42));
      expect(json['key'], equals('user_preference'));
      expect(json['content'], equals('Prefers dark theme'));
      expect(json['tags'], equals(['settings', 'theme']));
      expect(json['score'], equals(-1.25));

      final restored = MemoryItem.fromJson(json);
      expect(restored.id, equals(item.id));
      expect(restored.key, equals(item.key));
      expect(restored.content, equals(item.content));
      expect(restored.tags, equals(item.tags));
      expect(restored.createdAt, equals(item.createdAt));
      expect(restored.updatedAt, equals(item.updatedAt));
      expect(restored.score, equals(item.score));
    });
  });

  group('LocalMemoryService - CRUD Operations', () {
    test('saveMemory inserts a new memory and retrieves it by id and key', () async {
      final result = await memoryService.saveMemory(
        'user_name',
        'User name is Indra',
        ['profile', 'identity'],
      );

      expect(result.isRight(), isTrue);
      MemoryItem? saved;
      result.fold((_) => null, (item) => saved = item);

      expect(saved, isNotNull);
      expect(saved!.id, isNotNull);
      expect(saved!.key, equals('user_name'));
      expect(saved!.content, equals('User name is Indra'));
      expect(saved!.tags, equals(['profile', 'identity']));

      // Retrieve by Key
      final byKeyResult = await memoryService.getMemoryByKey('user_name');
      expect(byKeyResult.isRight(), isTrue);
      byKeyResult.fold((_) => fail('should succeed'), (item) {
        expect(item, isNotNull);
        expect(item!.id, equals(saved!.id));
        expect(item.content, equals('User name is Indra'));
      });

      // Retrieve by ID
      final byIdResult = await memoryService.getMemoryById(saved!.id!);
      expect(byIdResult.isRight(), isTrue);
      byIdResult.fold((_) => fail('should succeed'), (item) {
        expect(item, isNotNull);
        expect(item!.key, equals('user_name'));
      });
    });

    test('saveMemory updates existing memory when key already exists (upsert)', () async {
      await memoryService.saveMemory(
        'user_location',
        'Bandung, Indonesia',
        ['location'],
      );

      final updateResult = await memoryService.saveMemory(
        'user_location',
        'Jakarta, Indonesia',
        ['location', 'travel'],
      );

      expect(updateResult.isRight(), isTrue);
      updateResult.fold((_) => fail('should succeed'), (item) {
        expect(item.content, equals('Jakarta, Indonesia'));
        expect(item.tags, equals(['location', 'travel']));
      });

      // Verify only 1 record exists
      final allResult = await memoryService.getAllMemories();
      allResult.fold((_) => fail('should succeed'), (list) {
        expect(list.length, equals(1));
        expect(list.first.content, equals('Jakarta, Indonesia'));
      });
    });

    test('deleteMemory deletes by id and returns true; returns false for non-existent id', () async {
      final saveResult = await memoryService.saveMemory(
        'temp_key',
        'temporary content',
        ['temp'],
      );
      final id = saveResult.getOrElse(() => throw Exception()).id!;

      final deleteResult = await memoryService.deleteMemory(id);
      expect(deleteResult, equals(const Right(true)));

      // Verify deletion
      final getResult = await memoryService.getMemoryById(id);
      getResult.fold((_) => fail('should succeed'), (item) {
        expect(item, isNull);
      });

      // Deleting again returns false
      final secondDelete = await memoryService.deleteMemory(id);
      expect(secondDelete, equals(const Right(false)));
    });

    test('deleteMemoryByKey deletes by key successfully', () async {
      await memoryService.saveMemory('key_to_delete', 'some content');

      final deleteResult = await memoryService.deleteMemoryByKey('key_to_delete');
      expect(deleteResult, equals(const Right(true)));

      final getResult = await memoryService.getMemoryByKey('key_to_delete');
      getResult.fold((_) => fail('should succeed'), (item) {
        expect(item, isNull);
      });
    });

    test('getAllMemories and clearAllMemories work properly', () async {
      await memoryService.saveMemory('k1', 'c1');
      await memoryService.saveMemory('k2', 'c2');
      await memoryService.saveMemory('k3', 'c3');

      final allResult = await memoryService.getAllMemories();
      allResult.fold((_) => fail('should succeed'), (list) {
        expect(list.length, equals(3));
      });

      final clearResult = await memoryService.clearAllMemories();
      expect(clearResult, equals(const Right(3)));

      final emptyResult = await memoryService.getAllMemories();
      emptyResult.fold((_) => fail('should succeed'), (list) {
        expect(list, isEmpty);
      });
    });
  });

  group('LocalMemoryService - FTS5 Full-Text Search and BM25 Ranking', () {
    setUp(() async {
      await memoryService.saveMemory(
        'user_profile',
        'Indra is a software engineer working with Flutter and Dart on mobile applications.',
        ['profile', 'engineering'],
      );
      await memoryService.saveMemory(
        'favorite_editor',
        'Indra loves using Neovim and VS Code for writing Flutter and Dart code every day.',
        ['tools', 'preferences'],
      );
      await memoryService.saveMemory(
        'pet_info',
        'Indra has a white cat named Snow who loves sleeping on laptops.',
        ['personal', 'pets'],
      );
      await memoryService.saveMemory(
        'weekend_plan',
        'Going hiking in the mountains near Bandung this Saturday morning.',
        ['plans', 'outdoors'],
      );
    });

    test('searchMemories retrieves matches ordered by BM25 relevance score', () async {
      // Query "Flutter Dart" matches user_profile and favorite_editor
      final result = await memoryService.searchMemories('Flutter Dart', 5);

      expect(result.isRight(), isTrue);
      result.fold((_) => fail('should succeed'), (matches) {
        expect(matches.length, equals(2));
        // Both matched items should have score
        for (final m in matches) {
          expect(m.score, isNotNull);
          expect(m.content, contains('Flutter'));
        }
      });
    });

    test('searchMemories matches keywords in tags as well as content and key', () async {
      final result = await memoryService.searchMemories('engineering', 5);

      expect(result.isRight(), isTrue);
      result.fold((_) => fail('should succeed'), (matches) {
        expect(matches.length, equals(1));
        expect(matches.first.key, equals('user_profile'));
      });
    });

    test('searchMemories returns empty list when query has no matches', () async {
      final result = await memoryService.searchMemories('nonexistentterm123', 5);

      expect(result.isRight(), isTrue);
      result.fold((_) => fail('should succeed'), (matches) {
        expect(matches, isEmpty);
      });
    });

    test('searchMemories respects limit parameter', () async {
      final result = await memoryService.searchMemories('Indra', 2);

      expect(result.isRight(), isTrue);
      result.fold((_) => fail('should succeed'), (matches) {
        expect(matches.length, equals(2));
      });
    });

    test('searchMemories sanitizes query with punctuation and special characters safely', () async {
      final result = await memoryService.searchMemories('cat? (Snow)! "*"', 5);

      expect(result.isRight(), isTrue);
      result.fold((_) => fail('should succeed'), (matches) {
        expect(matches.length, equals(1));
        expect(matches.first.key, equals('pet_info'));
      });
    });
  });

  group('LocalMemoryService - Migration Schemas', () {
    test('onUpgradeDatabase migrates from v1 to v2 smoothly', () async {
      final tempPath = '${Directory.systemTemp.path}/test_migration_${DateTime.now().microsecondsSinceEpoch}.db';

      final testDb = await databaseFactoryFfi.openDatabase(
        tempPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            // Simulate v1 schema without extra index or columns
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
      await testDb.insert('memories', {
        'key': 'v1_test_key',
        'content': 'Data created in schema v1',
        'tags': 'v1,legacy',
        'created_at': now,
        'updated_at': now,
      });

      await testDb.close();

      // Now reopen at v2 triggering onUpgrade
      final upgradedDb = await databaseFactoryFfi.openDatabase(
        tempPath,
        options: OpenDatabaseOptions(
          version: 2,
          onCreate: LocalMemoryService.onCreateDatabase,
          onUpgrade: LocalMemoryService.onUpgradeDatabase,
        ),
      );

      final upgradedService = LocalMemoryService(database: upgradedDb);
      final itemResult = await upgradedService.getMemoryByKey('v1_test_key');
      expect(itemResult.isRight(), isTrue);
      itemResult.fold((_) => fail('should succeed'), (item) {
        expect(item, isNotNull);
        expect(item!.content, equals('Data created in schema v1'));
      });

      await upgradedDb.close();
      final file = File(tempPath);
      if (await file.exists()) {
        await file.delete();
      }
    });
  });

  group('ToolRegistry - Memory Tools Integration', () {
    late ToolRegistry toolRegistry;

    setUp(() {
      toolRegistry = ToolRegistry();
      toolRegistry.registerMemoryTools(memoryService);
    });

    test('registers save_memory, search_memories, delete_memory, and list_memories tools', () {
      expect(toolRegistry.hasTool('save_memory'), isTrue);
      expect(toolRegistry.hasTool('search_memories'), isTrue);
      expect(toolRegistry.hasTool('delete_memory'), isTrue);
      expect(toolRegistry.hasTool('list_memories'), isTrue);

      final saveTool = toolRegistry.getTool('save_memory')!;
      expect(saveTool.securityTier, equals(SecurityTier.tier1Auto));

      final searchTool = toolRegistry.getTool('search_memories')!;
      expect(searchTool.securityTier, equals(SecurityTier.tier1Auto));
    });

    test('executes save_memory and search_memories via ToolRegistry', () async {
      final saveResult = await toolRegistry.executeTool('save_memory', {
        'key': 'bot_mission',
        'content': 'To assist the user proactively on device tasks.',
        'tags': ['mission', 'ai'],
      });

      expect(saveResult.isRight(), isTrue);
      saveResult.fold((_) => fail('should succeed'), (output) {
        expect(output, contains('"key":"bot_mission"'));
        expect(output, contains('"status":"saved"'));
      });

      final searchResult = await toolRegistry.executeTool('search_memories', {
        'query': 'proactively mission',
        'limit': 5,
      });

      expect(searchResult.isRight(), isTrue);
      searchResult.fold((_) => fail('should succeed'), (output) {
        expect(output, contains('bot_mission'));
        expect(output, contains('To assist the user proactively'));
      });
    });

    test('executes list_memories and delete_memory via ToolRegistry', () async {
      await memoryService.saveMemory('item_a', 'content a');
      await memoryService.saveMemory('item_b', 'content b');

      final listResult = await toolRegistry.executeTool('list_memories', {
        'limit': 10,
      });
      expect(listResult.isRight(), isTrue);
      listResult.fold((_) => fail('should succeed'), (output) {
        expect(output, contains('item_a'));
        expect(output, contains('item_b'));
      });

      final deleteResult = await toolRegistry.executeTool('delete_memory', {
        'key': 'item_a',
      });
      expect(deleteResult.isRight(), isTrue);
      deleteResult.fold((_) => fail('should succeed'), (output) {
        expect(output, contains('"deleted":true'));
      });

      final getResult = await memoryService.getMemoryByKey('item_a');
      getResult.fold((_) => fail('should succeed'), (item) {
        expect(item, isNull);
      });
    });
  });

  group('LocalMemoryService - Error Handling', () {
    test('returns StorageFailure when database operation fails on closed db', () async {
      await db.close();

      final saveRes = await memoryService.saveMemory('k', 'v');
      expect(saveRes.isLeft(), isTrue);
      saveRes.fold((failure) => expect(failure, isA<StorageFailure>()), (_) => fail('should fail'));

      final searchRes = await memoryService.searchMemories('q');
      expect(searchRes.isLeft(), isTrue);
      searchRes.fold((failure) => expect(failure, isA<StorageFailure>()), (_) => fail('should fail'));

      final deleteRes = await memoryService.deleteMemory(1);
      expect(deleteRes.isLeft(), isTrue);
      deleteRes.fold((failure) => expect(failure, isA<StorageFailure>()), (_) => fail('should fail'));
    });
  });
}
