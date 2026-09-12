import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/common/exception.dart';
import 'package:flutter_ai_agent/data/datasources/remote/chat/sse_parser.dart';
import 'package:flutter_ai_agent/data/models/chat/chat_remote_response.dart';
import 'package:injectable/injectable.dart';

abstract class ChatDatasource {
  Future<Stream<ChatChunkRemoteResponse>> streamCompletion({
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    String? apiKey,
    double? temperature,
  });
}

@LazySingleton(as: ChatDatasource)
class ChatDatasourceImpl implements ChatDatasource {
  final Dio _dio;
  final SseParser _sseParser;

  ChatDatasourceImpl({required Dio dio, SseParser? sseParser})
      : _dio = dio,
        _sseParser = sseParser ?? SseParser();

  @override
  Future<Stream<ChatChunkRemoteResponse>> streamCompletion({
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    String? apiKey,
    double? temperature,
  }) async {
    final response = await _dio.post<ResponseBody>(
      '$baseUrl/chat/completions',
      data: jsonEncode({
        'model': model,
        'messages': messages,
        'stream': true,
        if (tools != null && tools.isNotEmpty) 'tools': tools,
        'temperature': ?temperature,
      }),
      options: Options(
        responseType: ResponseType.stream,
        headers: {
          'Content-Type': 'application/json',
          if (apiKey != null) 'Authorization': 'Bearer $apiKey',
        },
      ),
    );

    if (response.statusCode != 200) {
      throw ServerException(
        response.statusMessage ?? 'Server error occurred',
        response.statusCode,
      );
    }

    return response.data!.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty)
        .expand((line) => _sseParser.parse(line));
  }
}
