import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/session.dart';

abstract class ChatLocalRepository {
  Future<Either<Failure, List<ChatMessage>>> getMessages(String sessionId);
  Future<Either<Failure, void>> saveMessages(
    String sessionId,
    List<ChatMessage> messages,
  );
  Future<Either<Failure, void>> clearMessages(String sessionId);

  Future<Either<Failure, List<Session>>> getSessions(String profileId);
  Future<Either<Failure, Session>> createSession(
    String profileId, [
    String? title,
  ]);
  Future<Either<Failure, Session?>> getSession(int sessionId);
  Future<Either<Failure, void>> updateSessionTitle(
    int sessionId,
    String title,
  );
  Future<Either<Failure, void>> deleteSession(int sessionId);
}
