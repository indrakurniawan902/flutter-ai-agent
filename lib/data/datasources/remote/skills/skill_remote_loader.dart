import 'dart:convert';
import 'dart:typed_data';

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
  /// redirect that leaves the original host, returns a failure
  /// without issuing the next request.
  ///
  /// Size cap: the declared `Content-Length` is inspected before the body
  /// stream is touched, so an oversized declaration is refused without
  /// buffering a byte. A missing or lying header is still caught while
  /// reading: the stream is accumulated up to [maxDocumentBytes] and
  /// abandoned as soon as the running total exceeds it, and that post-read
  /// byte count remains authoritative.
  @override
  Future<Either<Failure, String>> fetchSkillMarkdown(String url) async {
    final invalid = SkillRemoteLoaderBase.validateSourceUrl(url);
    if (invalid != null) {
      return Left(ParseFailure(invalid));
    }
    var current = url;
    try {
      for (var redirects = 0; ; redirects++) {
        final response = await _dio.get<ResponseBody>(
          current,
          options: Options(
            responseType: ResponseType.stream,
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
          final currentHost = Uri.parse(current).host;
          final resolvedUri = Uri.tryParse(
            Uri.parse(current).resolve(location.trim()).toString(),
          );
          if (resolvedUri == null || resolvedUri.host != currentHost) {
            return const Left(
              NetworkFailure('Redirected to a different host'),
            );
          }
          current = resolvedUri.toString();
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
        if (body == null) {
          return Left(ParseFailure('Empty skill document at $url'));
        }
        final builder = BytesBuilder(copy: false);
        var exceeded = false;
        await for (final chunk in body.stream) {
          if (builder.length + chunk.length > maxDocumentBytes) {
            exceeded = true;
            break;
          }
          builder.add(chunk);
        }
        if (exceeded) {
          return const Left(
            ParseFailure('Skill document too large (max 256 KB)'),
          );
        }
        final bytes = builder.takeBytes();
        if (bytes.isEmpty) {
          return Left(ParseFailure('Empty skill document at $url'));
        }
        return Right(utf8.decode(bytes, allowMalformed: true));
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
