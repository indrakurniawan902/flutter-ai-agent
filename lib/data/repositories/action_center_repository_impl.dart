import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/exception.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/local/action_center/action_center_datasource.dart';
import 'package:flutter_ai_agent/data/models/action_center/action_item_model.dart';
import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';
import 'package:flutter_ai_agent/domain/repositories/action_center/action_center_repository.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: ActionCenterRepository)
class ActionCenterRepositoryImpl implements ActionCenterRepository {
  final ActionCenterDatasource _datasource;

  ActionCenterRepositoryImpl({required ActionCenterDatasource datasource})
      : _datasource = datasource;

  @override
  Future<Either<Failure, List<ActionItem>>> getItems() async {
    try {
      final items = await _datasource.getItems();
      return Right(items);
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to load action items: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> addItem(ActionItem item) async {
    try {
      await _datasource.addItem(ActionItemModel.fromEntity(item));
      return const Right(null);
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to save action item: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> markAsRead(String id) async {
    try {
      await _datasource.markAsRead(id);
      return const Right(null);
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to mark action item as read: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> dismiss(String id) async {
    try {
      await _datasource.dismiss(id);
      return const Right(null);
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to dismiss action item: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> clearAll() async {
    try {
      await _datasource.clearAll();
      return const Right(null);
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } catch (e) {
      return Left(CacheFailure('Failed to clear action items: $e'));
    }
  }
}
