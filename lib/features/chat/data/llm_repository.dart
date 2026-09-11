import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';

import 'package:flutter_ai_agent/common/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/models/chat_models.dart';
import 'package:flutter_ai_agent/features/chat/data/sse_parser.dart';

/// Repository for communicating with OpenAI-compatible LLM APIs.
///
/// Streams chat completions via SSE, parsing token and tool_call deltas.
class LlmRepository {
  final Dio dio;
  final SseParser _sseParser;

  LlmRepository({
    required this.dio,
    SseParser? sseParser,
  }) : _sseParser = sseParser ?? SseParser();

  /// Sends a chat completion request with streaming enabled.
  ///
  /// Returns `Either<Failure, Stream<ChatChunk>>` where the stream emits
  /// parsed ChatChunk objects from SSE lines.
  Future<Either<Failure, Stream<ChatChunk>>> streamCompletion({
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    String? apiKey,
  }) async {
    try {
      final response = await dio.post<ResponseBody>(
        '$baseUrl/chat/completions',
        data: jsonEncode({
          'model': model,
          'messages': messages,
          'stream': true,
          if (tools != null && tools.isNotEmpty) 'tools': tools,
        }),
        options: Options(
          responseType: ResponseType.stream,
          headers: {
            'Content-Type': 'application/json',
            if (apiKey != null) 'Authorization': 'Bearer $apiKey',
          },
        ),
      );

      final stream = response.data!.stream
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .where((line) => line.trim().isNotEmpty)
          .expand<ChatChunk>((line) => _sseParser.parse(line));

      return Right(stream);
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.connectionError) {
        return const Left(ConnectionFailure('Connection failed'));
      }
      if (e.type == DioExceptionType.badResponse) {
        return Left(ServerFailure(
          e.response?.statusMessage ?? 'Server error',
          e.response?.statusCode,
        ));
      }
      return Left(ConnectionFailure(e.message ?? 'Unknown error'));
    } on Exception catch (e) {
      return Left(ConnectionFailure(e.toString()));
    }
  }
}
