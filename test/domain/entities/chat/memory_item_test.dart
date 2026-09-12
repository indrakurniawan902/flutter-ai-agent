import 'package:flutter_ai_agent/domain/entities/chat/memory_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedCreated = DateTime(2026, 9, 11, 10, 0, 0);
  final fixedUpdated = DateTime(2026, 9, 11, 12, 30, 0);

  group('MemoryItem constructor', () {
    test('defaults tags to empty list', () {
      final item = MemoryItem(
        key: 'k',
        content: 'c',
        createdAt: fixedCreated,
        updatedAt: fixedUpdated,
      );
      expect(item.tags, isEmpty);
      expect(item.id, isNull);
      expect(item.score, isNull);
    });

    test('supports value equality', () {
      final a = MemoryItem(
        id: 1,
        key: 'user_name',
        content: 'Indra',
        tags: const ['profile'],
        createdAt: fixedCreated,
        updatedAt: fixedUpdated,
      );
      final b = MemoryItem(
        id: 1,
        key: 'user_name',
        content: 'Indra',
        tags: const ['profile'],
        createdAt: fixedCreated,
        updatedAt: fixedUpdated,
      );
      final c = a.copyWith(content: 'Other');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
      expect(a.props.length, 7);
    });
  });

  group('MemoryItem copyWith', () {
    test('updates specified fields and retains others', () {
      final item = MemoryItem(
        id: 1,
        key: 'k',
        content: 'v',
        tags: const ['a'],
        createdAt: fixedCreated,
        updatedAt: fixedUpdated,
      );
      final copy = item.copyWith(
        id: 2,
        key: 'k2',
        content: 'v2',
        tags: const ['b', 'c'],
        createdAt: fixedUpdated,
        updatedAt: fixedCreated,
        score: -1.5,
      );
      expect(copy.id, 2);
      expect(copy.key, 'k2');
      expect(copy.content, 'v2');
      expect(copy.tags, ['b', 'c']);
      expect(copy.createdAt, fixedUpdated);
      expect(copy.updatedAt, fixedCreated);
      expect(copy.score, -1.5);
    });

    test('retains original values when no args given', () {
      final item = MemoryItem(
        id: 1,
        key: 'k',
        content: 'v',
        tags: const ['a'],
        createdAt: fixedCreated,
        updatedAt: fixedUpdated,
        score: 0.5,
      );
      final copy = item.copyWith();
      expect(copy, equals(item));
    });
  });

  group('MemoryItem toJson / fromJson', () {
    test('toJson includes id and score when present', () {
      final item = MemoryItem(
        id: 42,
        key: 'user_preference',
        content: 'Prefers dark theme',
        tags: const ['settings', 'theme'],
        createdAt: fixedCreated,
        updatedAt: fixedUpdated,
        score: -1.25,
      );
      final json = item.toJson();
      expect(json['id'], 42);
      expect(json['key'], 'user_preference');
      expect(json['content'], 'Prefers dark theme');
      expect(json['tags'], ['settings', 'theme']);
      expect(json['createdAt'], fixedCreated.toIso8601String());
      expect(json['updatedAt'], fixedUpdated.toIso8601String());
      expect(json['score'], -1.25);
    });

    test('toJson omits id and score when null', () {
      final item = MemoryItem(
        key: 'k',
        content: 'c',
        createdAt: fixedCreated,
        updatedAt: fixedUpdated,
      );
      final json = item.toJson();
      expect(json.containsKey('id'), isFalse);
      expect(json.containsKey('score'), isFalse);
    });

    test('fromJson roundtrips toJson output', () {
      final item = MemoryItem(
        id: 42,
        key: 'user_preference',
        content: 'Prefers dark theme',
        tags: const ['settings', 'theme'],
        createdAt: fixedCreated,
        updatedAt: fixedUpdated,
        score: -1.25,
      );
      final restored = MemoryItem.fromJson(item.toJson());
      expect(restored.id, item.id);
      expect(restored.key, item.key);
      expect(restored.content, item.content);
      expect(restored.tags, item.tags);
      expect(restored.createdAt, item.createdAt);
      expect(restored.updatedAt, item.updatedAt);
      expect(restored.score, item.score);
    });

    test('fromJson parses comma-separated string tags', () {
      final item = MemoryItem.fromJson({
        'key': 'k',
        'content': 'c',
        'tags': 'a, b ,, c ',
        'createdAt': fixedCreated.toIso8601String(),
        'updatedAt': fixedUpdated.toIso8601String(),
      });
      expect(item.tags, ['a', 'b', 'c']);
    });

    test('fromJson trims and drops empty list tag entries', () {
      final item = MemoryItem.fromJson({
        'key': 'k',
        'content': 'c',
        'tags': [' a ', '', '  ', 'b'],
        'createdAt': fixedCreated.toIso8601String(),
        'updatedAt': fixedUpdated.toIso8601String(),
      });
      expect(item.tags, ['a', 'b']);
    });

    test('fromJson defaults tags to empty for missing or invalid', () {
      final missing = MemoryItem.fromJson({
        'key': 'k',
        'content': 'c',
      });
      expect(missing.tags, isEmpty);

      final emptyString = MemoryItem.fromJson({
        'key': 'k',
        'content': 'c',
        'tags': '',
      });
      expect(emptyString.tags, isEmpty);

      final numeric = MemoryItem.fromJson({
        'key': 'k',
        'content': 'c',
        'tags': 123,
      });
      expect(numeric.tags, isEmpty);
    });

    test('fromJson parses epoch millis datetimes', () {
      final item = MemoryItem.fromJson({
        'key': 'k',
        'content': 'c',
        'createdAt': fixedCreated.millisecondsSinceEpoch,
        'updatedAt': fixedUpdated.millisecondsSinceEpoch,
      });
      expect(item.createdAt, fixedCreated);
      expect(item.updatedAt, fixedUpdated);
    });

    test('fromJson supports snake_case datetime keys', () {
      final item = MemoryItem.fromJson({
        'key': 'k',
        'content': 'c',
        'created_at': fixedCreated.toIso8601String(),
        'updated_at': fixedUpdated.toIso8601String(),
      });
      expect(item.createdAt, fixedCreated);
      expect(item.updatedAt, fixedUpdated);
    });

    test('fromJson falls back to now for missing or invalid datetimes', () {
      final before = DateTime.now();
      final missing = MemoryItem.fromJson({'key': 'k', 'content': 'c'});
      final after = DateTime.now();
      expect(missing.createdAt.isAfter(before.subtract(const Duration(seconds: 5))), isTrue);
      expect(missing.createdAt.isBefore(after.add(const Duration(seconds: 5))), isTrue);

      final invalid = MemoryItem.fromJson({
        'key': 'k',
        'content': 'c',
        'createdAt': 'not-a-date',
        'updatedAt': 'not-a-date',
      });
      expect(invalid.createdAt.isAfter(before.subtract(const Duration(seconds: 5))), isTrue);
      expect(invalid.updatedAt.isAfter(before.subtract(const Duration(seconds: 5))), isTrue);
    });

    test('fromJson defaults missing key content id score', () {
      final item = MemoryItem.fromJson({});
      expect(item.id, isNull);
      expect(item.key, isEmpty);
      expect(item.content, isEmpty);
      expect(item.score, isNull);
    });

    test('fromJson parses numeric score to double', () {
      final item = MemoryItem.fromJson({
        'key': 'k',
        'content': 'c',
        'score': 3,
      });
      expect(item.score, 3.0);
    });
  });

  group('MemoryItem toDbMap / fromDbMap', () {
    test('toDbMap joins tags and uses epoch millis', () {
      final item = MemoryItem(
        id: 7,
        key: 'k',
        content: 'c',
        tags: const ['a', 'b'],
        createdAt: fixedCreated,
        updatedAt: fixedUpdated,
      );
      final map = item.toDbMap();
      expect(map['id'], 7);
      expect(map['key'], 'k');
      expect(map['content'], 'c');
      expect(map['tags'], 'a,b');
      expect(map['created_at'], fixedCreated.millisecondsSinceEpoch);
      expect(map['updated_at'], fixedUpdated.millisecondsSinceEpoch);
    });

    test('toDbMap omits id when null', () {
      final item = MemoryItem(
        key: 'k',
        content: 'c',
        createdAt: fixedCreated,
        updatedAt: fixedUpdated,
      );
      expect(item.toDbMap().containsKey('id'), isFalse);
    });

    test('fromDbMap roundtrips toDbMap output', () {
      final item = MemoryItem(
        id: 7,
        key: 'k',
        content: 'c',
        tags: const ['a', 'b'],
        createdAt: DateTime.fromMillisecondsSinceEpoch(
            fixedCreated.millisecondsSinceEpoch),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(
            fixedUpdated.millisecondsSinceEpoch),
      );
      final restored = MemoryItem.fromDbMap(item.toDbMap());
      expect(restored.id, item.id);
      expect(restored.key, item.key);
      expect(restored.content, item.content);
      expect(restored.tags, item.tags);
      expect(restored.createdAt, item.createdAt);
      expect(restored.updatedAt, item.updatedAt);
    });

    test('fromDbMap parses comma tags with whitespace', () {
      final item = MemoryItem.fromDbMap({
        'id': 1,
        'key': 'k',
        'content': 'c',
        'tags': 'a, b ,, c ',
        'created_at': 1000,
        'updated_at': 2000,
      });
      expect(item.tags, ['a', 'b', 'c']);
    });

    test('fromDbMap defaults empty tags', () {
      final empty = MemoryItem.fromDbMap({
        'id': 1,
        'key': 'k',
        'content': 'c',
        'tags': '',
        'created_at': 1000,
        'updated_at': 2000,
      });
      expect(empty.tags, isEmpty);

      final missing = MemoryItem.fromDbMap({
        'id': 1,
        'key': 'k',
        'content': 'c',
        'created_at': 1000,
        'updated_at': 2000,
      });
      expect(missing.tags, isEmpty);
    });

    test('fromDbMap falls back to rowid when id missing', () {
      final item = MemoryItem.fromDbMap({
        'rowid': 9,
        'key': 'k',
        'content': 'c',
        'tags': '',
        'created_at': 1000,
        'updated_at': 2000,
      });
      expect(item.id, 9);
    });

    test('fromDbMap yields null id when id and rowid missing', () {
      final item = MemoryItem.fromDbMap({
        'key': 'k',
        'content': 'c',
        'tags': '',
        'created_at': 1000,
        'updated_at': 2000,
      });
      expect(item.id, isNull);
    });

    test('fromDbMap reads bm25 rank as score', () {
      final item = MemoryItem.fromDbMap({
        'id': 1,
        'key': 'k',
        'content': 'c',
        'tags': '',
        'created_at': 1000,
        'updated_at': 2000,
        'rank': -0.75,
      });
      expect(item.score, -0.75);
    });

    test('fromDbMap explicit score arg overrides rank', () {
      final item = MemoryItem.fromDbMap(
        {
          'id': 1,
          'key': 'k',
          'content': 'c',
          'tags': '',
          'created_at': 1000,
          'updated_at': 2000,
          'rank': -0.75,
        },
        -2.0,
      );
      expect(item.score, -2.0);
    });

    test('fromDbMap defaults missing key content epochs', () {
      final item = MemoryItem.fromDbMap({});
      expect(item.key, isEmpty);
      expect(item.content, isEmpty);
      expect(item.createdAt,
          DateTime.fromMillisecondsSinceEpoch(0));
      expect(item.updatedAt,
          DateTime.fromMillisecondsSinceEpoch(0));
      expect(item.score, isNull);
    });
  });
}
