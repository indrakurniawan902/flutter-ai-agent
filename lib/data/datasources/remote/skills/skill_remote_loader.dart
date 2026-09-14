import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/services/skills/skill_remote_loader.dart';

/// Dio-backed remote loader for SKILL.md documents.
@LazySingleton(as: SkillRemoteLoaderBase)
class SkillRemoteLoader implements SkillRemoteLoaderBase {
  SkillRemoteLoader({Dio? dio}) : _dio = dio ?? Dio();

  @factoryMethod
  factory SkillRemoteLoader.create(Dio dio) => SkillRemoteLoader(dio: dio);

  final Dio _dio;

  /// Hard cap for a fetched skill document.
  static const int maxDocumentBytes = 256 * 1024;

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Mobile Safari/537.36';

  static const String _accept = 'text/plain, text/markdown, */*';

  @override
  Future<Either<Failure, String>> fetchSkillMarkdown(String url) async {
    final invalid = SkillRemoteLoaderBase.validateSourceUrl(url);
    if (invalid != null) {
      return Left(ParseFailure(invalid));
    }
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          headers: const {'User-Agent': _userAgent, 'Accept': _accept},
        ),
      );
      final body = response.data;
      if (body == null || body.isEmpty) {
        return Left(ParseFailure('Empty skill document at $url'));
      }
      if (body.length > maxDocumentBytes) {
        return const Left(
          ParseFailure('Skill document too large (max 256 KB)'),
        );
      }
      return Right(body);
    } on DioException catch (e) {
      return Left(
        NetworkFailure('Failed to fetch skill: ${e.message ?? e.type.name}'),
      );
    } catch (e) {
      return Left(NetworkFailure('Failed to fetch skill: $e'));
    }
  }
}
