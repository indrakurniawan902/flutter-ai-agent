import 'dart:convert';
import 'dart:io';

import 'package:flutter_ai_agent/data/datasources/local/action_center/action_center_datasource.dart';
import 'package:flutter_ai_agent/data/models/action_center/action_item_model.dart';
import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';

void main() {
  late Directory tempDir;
  late Box<String> box;
  late ActionCenterDatasourceImpl datasource;

  ActionItemModel buildItem({
    required String id,
    required DateTime timestamp,
    String title = 'Title',
    String summary = 'Summary',
    ActionItemPriority priority = ActionItemPriority.normal,
    bool isRead = false,
    Map<String, dynamic>? payload,
    String source = 'battery_watchdog',
  }) {
    return ActionItemModel(
      id: id,
      title: title,
      summary: summary,
      timestamp: timestamp,
      priority: priority,
      isRead: isRead,
      actionPayload: payload,
      source: source,
    );
  }

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('action_center_test');
    Hive.init(tempDir.path);
    box = await Hive.openBox<String>(ActionCenterDatasourceImpl.boxName);
    datasource = ActionCenterDatasourceImpl(box: box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  group('addItem + getItems roundtrip', () {
    test('persists item and reads it back with all fields', () async {
      final item = buildItem(
        id: 'a1',
        timestamp: DateTime.utc(2026, 1, 1, 10),
        title: 'Battery low',
        summary: 'Below 20 percent',
        priority: ActionItemPriority.high,
        payload: const {'level': 15},
        source: 'battery_watchdog',
      );

      await datasource.addItem(item);
      final result = await datasource.getItems();

      expect(result, hasLength(1));
      expect(result.first.id, 'a1');
      expect(result.first.title, 'Battery low');
      expect(result.first.summary, 'Below 20 percent');
      expect(result.first.timestamp, item.timestamp);
      expect(result.first.priority, ActionItemPriority.high);
      expect(result.first.isRead, isFalse);
      expect(result.first.actionPayload, {'level': 15});
      expect(result.first.source, 'battery_watchdog');
    });

    test('replaces item with same id', () async {
      await datasource.addItem(
        buildItem(id: 'a1', timestamp: DateTime.utc(2026, 1, 1), title: 'Old'),
      );
      await datasource.addItem(
        buildItem(id: 'a1', timestamp: DateTime.utc(2026, 1, 1), title: 'New'),
      );

      final result = await datasource.getItems();
      expect(result, hasLength(1));
      expect(result.first.title, 'New');
    });
  });

  group('getItems ordering', () {
    test('returns items sorted newest-first', () async {
      await datasource.addItem(
        buildItem(id: 'old', timestamp: DateTime.utc(2026, 1, 1)),
      );
      await datasource.addItem(
        buildItem(id: 'new', timestamp: DateTime.utc(2026, 3, 1)),
      );
      await datasource.addItem(
        buildItem(id: 'mid', timestamp: DateTime.utc(2026, 2, 1)),
      );

      final result = await datasource.getItems();
      expect(result.map((e) => e.id).toList(), ['new', 'mid', 'old']);
    });

    test('returns empty list when box is empty', () async {
      expect(await datasource.getItems(), isEmpty);
    });
  });

  group('corrupted JSON entry', () {
    test('is skipped and does not throw', () async {
      await box.put('good', jsonEncode(buildItem(
        id: 'good',
        timestamp: DateTime.utc(2026, 1, 1),
      ).toJson()));
      await box.put('broken', '{not valid json');
      await box.put('notamap', jsonEncode(42));

      final result = await datasource.getItems();

      expect(result, hasLength(1));
      expect(result.first.id, 'good');
    });
  });

  group('markAsRead', () {
    test('sets isRead true while preserving other fields', () async {
      await datasource.addItem(buildItem(
        id: 'a1',
        timestamp: DateTime.utc(2026, 1, 1),
        title: 'Keep me',
        priority: ActionItemPriority.high,
        payload: const {'k': 'v'},
      ));

      await datasource.markAsRead('a1');
      final result = await datasource.getItems();

      expect(result.first.isRead, isTrue);
      expect(result.first.title, 'Keep me');
      expect(result.first.priority, ActionItemPriority.high);
      expect(result.first.actionPayload, {'k': 'v'});
    });

    test('missing id is a no-op', () async {
      await datasource.markAsRead('nope');
      expect(await datasource.getItems(), isEmpty);
    });

    test('corrupted entry is left untouched, no throw', () async {
      await box.put('broken', '{not valid json');
      await datasource.markAsRead('broken');
      expect(box.get('broken'), '{not valid json');
    });
  });

  group('dismiss', () {
    test('removes the item', () async {
      await datasource.addItem(
        buildItem(id: 'a1', timestamp: DateTime.utc(2026, 1, 1)),
      );

      await datasource.dismiss('a1');

      expect(await datasource.getItems(), isEmpty);
    });

    test('missing id is a no-op', () async {
      await datasource.dismiss('nope');
      expect(await datasource.getItems(), isEmpty);
    });
  });

  group('clearAll', () {
    test('empties the box', () async {
      await datasource.addItem(
        buildItem(id: 'a1', timestamp: DateTime.utc(2026, 1, 1)),
      );
      await datasource.addItem(
        buildItem(id: 'a2', timestamp: DateTime.utc(2026, 1, 2)),
      );

      await datasource.clearAll();

      expect(await datasource.getItems(), isEmpty);
    });
  });
}
