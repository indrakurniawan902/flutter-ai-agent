import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/memory_item.dart';

abstract class LocalMemoryServiceBase {
  Future<Either<Failure, MemoryItem>> saveMemory(
    String key,
    String content, [
    List<String> tags = const [],
  ]);

  Future<Either<Failure, List<MemoryItem>>> searchMemories(
    String query, [
    int limit = 5,
  ]);

  Future<Either<Failure, bool>> deleteMemory(int id);

  Future<Either<Failure, bool>> deleteMemoryByKey(String key);

  Future<Either<Failure, MemoryItem?>> getMemoryByKey(String key);

  Future<Either<Failure, MemoryItem?>> getMemoryById(int id);

  Future<Either<Failure, List<MemoryItem>>> getAllMemories({int limit = 100});

  Future<Either<Failure, int>> clearAllMemories();

  Future<Either<Failure, String>> saveMemoryFormattedJson(
    Map<String, dynamic> args,
  );

  Future<Either<Failure, String>> searchMemoriesFormattedJson(
    Map<String, dynamic> args,
  );

  Future<Either<Failure, String>> deleteMemoryFormattedJson(
    Map<String, dynamic> args,
  );

  Future<Either<Failure, String>> listMemoriesFormattedJson([
    Map<String, dynamic> args,
  ]);
}
