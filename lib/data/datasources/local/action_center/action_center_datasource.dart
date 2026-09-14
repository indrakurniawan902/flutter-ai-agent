import 'dart:convert';

import 'package:flutter_ai_agent/common/exception.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/data/models/action_center/action_item_model.dart';
import 'package:hive_ce/hive.dart';
import 'package:injectable/injectable.dart';

abstract class ActionCenterDatasource {
  Future<List<ActionItemModel>> getItems();
  Future<void> addItem(ActionItemModel item);
  Future<void> markAsRead(String id);
  Future<void> dismiss(String id);
  Future<void> clearAll();
}

/// Hive-backed store for the Action Center inbox.
///
/// Entries are stored as JSON-encoded strings keyed by item id, so no
/// generated [TypeAdapter] is required.
@LazySingleton(as: ActionCenterDatasource)
class ActionCenterDatasourceImpl implements ActionCenterDatasource {
  static const String boxName = 'action_center';

  final Box<String> _box;

  ActionCenterDatasourceImpl({required Box<String> box}) : _box = box;

  /// Opens (or reuses) the Hive box and returns a ready datasource.
  @factoryMethod
  static Future<ActionCenterDatasourceImpl> create() async {
    final box = await Hive.openBox<String>(boxName);
    return ActionCenterDatasourceImpl(box: box);
  }

  @override
  Future<List<ActionItemModel>> getItems() async {
    try {
      final items = <ActionItemModel>[];
      for (final raw in _box.values) {
        final model = _decode(raw);
        if (model != null) items.add(model);
      }
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return items;
    } catch (e) {
      throw CacheException(
        FailureMessage.humanize(e, context: 'Failed to load action items'),
      );
    }
  }

  @override
  Future<void> addItem(ActionItemModel item) async {
    try {
      await _box.put(item.id, jsonEncode(item.toJson()));
    } catch (e) {
      throw CacheException(
        FailureMessage.humanize(e, context: 'Failed to save action item'),
      );
    }
  }

  @override
  Future<void> markAsRead(String id) async {
    try {
      final existing = _box.get(id);
      if (existing == null) return;
      final model = _decode(existing);
      if (model == null) return;
      await _box.put(
        id,
        jsonEncode(
          ActionItemModel.fromEntity(
            model.copyWith(isRead: true),
          ).toJson(),
        ),
      );
    } catch (e) {
      throw CacheException(
        FailureMessage.humanize(
          e,
          context: 'Failed to mark action item as read',
        ),
      );
    }
  }

  @override
  Future<void> dismiss(String id) async {
    try {
      await _box.delete(id);
    } catch (e) {
      throw CacheException(
        FailureMessage.humanize(
          e,
          context: 'Failed to dismiss action item',
        ),
      );
    }
  }

  @override
  Future<void> clearAll() async {
    try {
      await _box.clear();
    } catch (e) {
      throw CacheException(
        FailureMessage.humanize(e, context: 'Failed to clear action items'),
      );
    }
  }

  /// Decodes a stored JSON string, returning null for corrupted entries
  /// so a single bad value never breaks the whole read.
  ActionItemModel? _decode(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return ActionItemModel.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }
}
