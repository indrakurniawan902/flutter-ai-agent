import 'package:dartz/dartz.dart';
import 'package:dio/dio.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/tools/chat/url_reader_service.dart';

/// Fetches web pages and reduces them to readable plain text.
///
/// The remaining static members are pure HTML helpers (no I/O) used by the
/// `read_web_page` tool; URL detection lives on [UrlReaderServiceBase].
@LazySingleton(as: UrlReaderServiceBase)
class UrlReaderService implements UrlReaderServiceBase {
  UrlReaderService({Dio? dio}) : _dio = dio ?? Dio();

  @factoryMethod
  factory UrlReaderService.create(Dio dio) => UrlReaderService(dio: dio);

  final Dio _dio;

  /// Hard cap for injected context.
  static const int defaultMaxChars = 20000;

  static const String _userAgent =
      'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/126.0.0.0 Mobile Safari/537.36';

  static const String _accept =
      'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';

  static const String _acceptLanguage = 'en-US,en;q=0.9';

  static final RegExp _blockTagRegExp = RegExp(
    r'</?(?:br|p|div|li|tr|h[1-6]|section|article|blockquote|pre|table|ul|ol|header|footer|nav|aside)\b[^>]*>',
    caseSensitive: false,
  );

  /// Fetches [url] and returns the raw response body (HTML).
  Future<Either<Failure, String>> fetchUrl(String url) async {
    try {
      final response = await _dio.get<String>(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          headers: const {
            'User-Agent': _userAgent,
            'Accept': _accept,
            'Accept-Language': _acceptLanguage,
          },
        ),
      );
      final body = response.data;
      if (body == null || body.trim().isEmpty) {
        return Left(ParseFailure('No readable content found at $url'));
      }
      return Right(body);
    } on DioException catch (e) {
      return Left(NetworkFailure(_describeDioError(e, url)));
    } catch (e) {
      return Left(NetworkFailure('Failed to fetch $url: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> fetchReadableText(String url) async {
    final validationError = UrlReaderServiceBase.validateUrl(url);
    if (validationError != null) {
      return Left(ValidationFailure(validationError));
    }

    final fetched = await fetchUrl(url);
    if (fetched.isLeft()) {
      return fetched;
    }

    final html = fetched.getOrElse(() => '');
    final title = extractTitle(html);
    final text = htmlToPlainText(html);
    if (text.trim().isEmpty) {
      return Left(ParseFailure('No readable content found at $url'));
    }

    final body = title.isEmpty ? text : '$title\n\n$text';
    return Right(capText(body));
  }

  static String _describeDioError(DioException e, String url) {
    final status = e.response?.statusCode;
    if (status != null) return 'HTTP $status while fetching $url';
    return 'Failed to fetch $url: ${e.message ?? e.type.name}';
  }

  /// Text of `<title>…</title>`, entity-decoded and whitespace-collapsed.
  static String extractTitle(String html) {
    final match = RegExp(
      r'<title[^>]*>([\s\S]*?)</title>',
      caseSensitive: false,
    ).firstMatch(html);
    if (match == null) return '';
    final rawTitle = match.group(1) ?? '';
    return _collapseWhitespace(_decodeEntities(rawTitle)).trim();
  }

  /// Strips markup, scripts and styles from [html], returning plain text.
  static String htmlToPlainText(String html) {
    var text = html;

    for (final tag in const [
      'script',
      'style',
      'noscript',
      'svg',
      'iframe',
    ]) {
      text = text.replaceAll(
        RegExp('<$tag\\b[^>]*>[\\s\\S]*?</$tag\\s*>',
            caseSensitive: false, dotAll: true),
        ' ',
      );
      text = text.replaceAll(
        RegExp('<$tag\\b[^>]*/>', caseSensitive: false, dotAll: true),
        ' ',
      );
    }

    text = text.replaceAll(
      RegExp(r'<!--[\s\S]*?-->', caseSensitive: false, dotAll: true),
      ' ',
    );

    text = text.replaceAll(_blockTagRegExp, '\n');

    text = text.replaceAll(RegExp(r'<[^>]*>'), '');

    text = _decodeEntities(text);

    final lines = text
        .split('\n')
        .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();

    return lines.join('\n').trim();
  }

  /// Caps [text] to [maxChars], preferring a word/sentence boundary.
  static String capText(String text, [int maxChars = defaultMaxChars]) {
    const marker = '\n\n…[truncated]';
    if (maxChars <= 0) return '…[truncated]';
    if (text.length <= maxChars) return text;

    final window = text.substring(0, maxChars);
    final boundaryStart = (maxChars * 0.8).floor();
    var cut = maxChars;
    for (var i = maxChars - 1; i >= boundaryStart && i > 0; i--) {
      final char = window[i];
      if (char == '\n' || char == ' ') {
        cut = i;
        break;
      }
    }
    return '${text.substring(0, cut)}$marker';
  }

  static String _collapseWhitespace(String value) =>
      value.replaceAll(RegExp(r'\s+'), ' ');

  static String _decodeEntities(String value) {
    var result = value;
    const namedEntities = {
      'nbsp': ' ',
      'amp': '&',
      'lt': '<',
      'gt': '>',
      'quot': '"',
      'apos': "'",
      'mdash': '—',
      'ndash': '–',
      'hellip': '…',
      'rsquo': '’',
      'lsquo': '‘',
      'ldquo': '“',
      'rdquo': '”',
    };

    result = result.replaceAllMapped(
      RegExp(r'&([A-Za-z][A-Za-z0-9]*);'),
      (match) {
        final name = (match.group(1) ?? '').toLowerCase();
        final replacement = namedEntities[name];
        if (replacement != null) return replacement;
        return match.group(0) ?? '';
      },
    );

    result = result.replaceAllMapped(
      RegExp(r'&#x([0-9A-Fa-f]+);'),
      (match) => _codePoint(match.group(1), 16),
    );
    result = result.replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (match) => _codePoint(match.group(1), 10),
    );

    return result;
  }

  static String _codePoint(String? raw, int radix) {
    if (raw == null || raw.isEmpty) return '';
    final code = int.tryParse(raw, radix: radix);
    if (code == null || code < 0 || code > 0x10FFFF) return '';
    if (code >= 0xD800 && code <= 0xDFFF) return '';
    return String.fromCharCode(code);
  }
}
