import 'dart:convert';

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

  /// Followed redirect hops before the fetch fails closed.
  static const int _maxRedirects = 3;

  /// Fetches a raw SKILL.md document, following at most [_maxRedirects]
  /// redirects manually so every hop's host is validated BEFORE the next
  /// request is sent.
  ///
  /// Dio's automatic redirect following cannot be used here: the only
  /// post-hoc signal is `response.realUri`, which dio derives from the
  /// adapter-dependent `redirects` list and silently falls back to the
  /// ORIGINAL url when that list is empty, making a host check a no-op.
  /// Manual following is fail-closed: a 3xx without a location, or a
  /// redirect that resolves to a disallowed host, returns a failure
  /// without issuing the next request.
  ///
  /// Size cap: dio 5.11.1 cannot cap an unknown-length stream, so the
  /// post-download `utf8.encode(body).length` check remains authoritative;
  /// a declared `Content-Length` above [maxDocumentBytes] is refused
  /// before the body is buffered.
  @override
  Future<Either<Failure, String>> fetchSkillMarkdown(String url) async {
    final invalid = SkillRemoteLoaderBase.validateSourceUrl(url);
    if (invalid != null) {
      return Left(ParseFailure(invalid));
    }
    var current = url;
    try {
      for (var redirects = 0; ; redirects++) {
        final response = await _dio.get<String>(
          current,
          options: Options(
            responseType: ResponseType.plain,
            followRedirects: false,
            validateStatus: (code) => code != null && code >= 200 && code < 400,
            headers: const {'User-Agent': _userAgent, 'Accept': _accept},
          ),
        );
        final status = response.statusCode ?? 0;
        if (status >= 300) {
          if (redirects >= _maxRedirects) {
            return const Left(NetworkFailure('Too many redirects'));
          }
          final location = response.headers.value('location');
          if (location == null || location.trim().isEmpty) {
            return const Left(
              NetworkFailure('Redirected without a location header'),
            );
          }
          final resolved = Uri.parse(
            current,
          ).resolve(location.trim()).toString();
          final redirectInvalid = SkillRemoteLoaderBase.validateSourceUrl(
            resolved,
          );
          if (redirectInvalid != null) {
            return const Left(
              NetworkFailure('Redirected to a disallowed host'),
            );
          }
          current = resolved;
          continue;
        }
        final declaredLength = response.headers.value(
          Headers.contentLengthHeader,
        );
        if (declaredLength != null) {
          final parsed = int.tryParse(declaredLength.trim());
          if (parsed != null && parsed > maxDocumentBytes) {
            return const Left(
              NetworkFailure('Skill document too large (max 256 KB)'),
            );
          }
        }
        final body = response.data;
        if (body == null || body.isEmpty) {
          return Left(ParseFailure('Empty skill document at $url'));
        }
        if (utf8.encode(body).length > maxDocumentBytes) {
          return const Left(
            ParseFailure('Skill document too large (max 256 KB)'),
          );
        }
        return Right(body);
      }
    } on DioException catch (e) {
      return Left(
        NetworkFailure('Failed to fetch skill: ${e.message ?? e.type.name}'),
      );
    } catch (e) {
      return Left(NetworkFailure('Failed to fetch skill: $e'));
    }
  }
}
