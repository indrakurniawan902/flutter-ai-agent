import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';

abstract class ChatLocalRepository {
  Future<Either<Failure, List<ChatMessage>>> getMessages(String profileId);
  Future<Either<Failure, void>> saveMessages(
    String profileId,
    List<ChatMessage> messages,
  );
  Future<Either<Failure, void>> clearMessages(String profileId);
}
