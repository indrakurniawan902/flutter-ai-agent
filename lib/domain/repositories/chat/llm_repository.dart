import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';

abstract class LlmRepository {
  Future<Either<Failure, Stream<ChatChunk>>> streamCompletion({
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    String? apiKey,
  });
}
