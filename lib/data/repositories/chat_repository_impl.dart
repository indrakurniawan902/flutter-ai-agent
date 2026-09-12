import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:flutter_ai_agent/common/exception.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/remote/chat/chat_datasource.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart';
import 'package:flutter_ai_agent/utils/dio_err_handler.dart';
import 'package:injectable/injectable.dart';

@LazySingleton(as: LlmRepository)
class LlmRepositoryImpl implements LlmRepository {
  final ChatDatasource _datasource;
  final DioErrHandler _dioErrHandler;

  LlmRepositoryImpl({
    required ChatDatasource datasource,
    DioErrHandler? dioErrHandler,
  }) : _datasource = datasource,
        _dioErrHandler = dioErrHandler ?? const DioErrHandler();

  @override
  Future<Either<Failure, Stream<ChatChunk>>> streamCompletion({
    required String baseUrl,
    required String model,
    required List<Map<String, dynamic>> messages,
    List<Map<String, dynamic>>? tools,
    String? apiKey,
    double? temperature,
  }) async {
    try {
      final stream = await _datasource.streamCompletion(
        baseUrl: baseUrl,
        model: model,
        messages: messages,
        tools: tools,
        apiKey: apiKey,
        temperature: temperature,
      );
      return Right(stream.map((chunk) => chunk.toDomain()));
    } on DioException catch (e) {
      return Left(ConnectionFailure(_dioErrHandler.handleDioError(e)));
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message, e.statusCode));
    } on CacheException catch (e) {
      return Left(CacheFailure(e.message));
    } on Exception catch (e) {
      return Left(ConnectionFailure(e.toString()));
    }
  }
}
