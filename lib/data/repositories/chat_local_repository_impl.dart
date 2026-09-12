import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/local/chat/chat_local_datasource.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/chat_local_repository.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: ChatLocalRepository)
class ChatLocalRepositoryImpl implements ChatLocalRepository {
  final ChatLocalDatasource _datasource;

  ChatLocalRepositoryImpl({required ChatLocalDatasource datasource})
      : _datasource = datasource;

  @override
  Future<Either<Failure, List<ChatMessage>>> getMessages(
    String profileId,
  ) async {
    try {
      final messages = await _datasource.getMessages(profileId);
      return Right(messages);
    } catch (e) {
      return Left(CacheFailure('Failed to load chat history: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> saveMessages(
    String profileId,
    List<ChatMessage> messages,
  ) async {
    try {
      await _datasource.saveMessages(profileId, messages);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('Failed to save chat history: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> clearMessages(String profileId) async {
    try {
      await _datasource.clearMessages(profileId);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('Failed to clear chat history: $e'));
    }
  }
}
