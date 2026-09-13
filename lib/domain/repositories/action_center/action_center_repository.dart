import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';

/// Contract for the Action Center inbox persistence layer.
abstract class ActionCenterRepository {
  /// Returns all stored action items, sorted newest-first by timestamp.
  Future<Either<Failure, List<ActionItem>>> getItems();

  /// Inserts or replaces a single [item] keyed by its id.
  Future<Either<Failure, void>> addItem(ActionItem item);

  /// Flags the item with [id] as read. Missing ids are ignored.
  Future<Either<Failure, void>> markAsRead(String id);

  /// Removes the item with [id]. Missing ids are ignored.
  Future<Either<Failure, void>> dismiss(String id);

  /// Empties the inbox.
  Future<Either<Failure, void>> clearAll();
}
