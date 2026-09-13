import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/local/chat/chat_local_datasource.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/session.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/chat_local_repository.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: ChatLocalRepository)
class ChatLocalRepositoryImpl implements ChatLocalRepository {
  static const int maxTitleLength = 40;
  static const String untitledSessionTitle = 'New chat';

  final ChatLocalDatasource _datasource;

  ChatLocalRepositoryImpl({required ChatLocalDatasource datasource})
      : _datasource = datasource;

  /// Derives a session title from the first user message, truncated to
  /// [maxTitleLength] characters. Falls back to [untitledSessionTitle].
  static String titleFromMessage(String? message) {
    final normalized =
        (message ?? '').trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) return untitledSessionTitle;
    if (normalized.length <= maxTitleLength) return normalized;
    return normalized.substring(0, maxTitleLength);
  }

  @override
  Future<Either<Failure, List<ChatMessage>>> getMessages(
    String sessionId,
  ) async {
    try {
      final messages = await _datasource.getMessages(sessionId);
      return Right(messages);
    } catch (e) {
      return Left(CacheFailure('Failed to load chat history: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> saveMessages(
    String sessionId,
    List<ChatMessage> messages,
  ) async {
    try {
      await _datasource.saveMessages(sessionId, messages);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('Failed to save chat history: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> clearMessages(String sessionId) async {
    try {
      await _datasource.clearMessages(sessionId);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('Failed to clear chat history: $e'));
    }
  }

  @override
  Future<Either<Failure, List<Session>>> getSessions(String profileId) async {
    try {
      final sessions = await _datasource.getSessions(profileId);
      return Right(sessions);
    } catch (e) {
      return Left(CacheFailure('Failed to load chat sessions: $e'));
    }
  }

  @override
  Future<Either<Failure, Session>> createSession(
    String profileId, [
    String? title,
  ]) async {
    try {
      final resolvedTitle = titleFromMessage(title);
      final session = await _datasource.createSession(
        profileId,
        resolvedTitle,
      );
      return Right(session);
    } catch (e) {
      return Left(CacheFailure('Failed to create chat session: $e'));
    }
  }

  @override
  Future<Either<Failure, Session?>> getSession(int sessionId) async {
    try {
      final session = await _datasource.getSession(sessionId);
      return Right(session);
    } catch (e) {
      return Left(CacheFailure('Failed to load chat session: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> updateSessionTitle(
    int sessionId,
    String title,
  ) async {
    try {
      await _datasource.updateSessionTitle(
        sessionId,
        titleFromMessage(title),
      );
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('Failed to update chat session title: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteSession(int sessionId) async {
    try {
      await _datasource.deleteSession(sessionId);
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('Failed to delete chat session: $e'));
    }
  }
}
