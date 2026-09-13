import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

abstract class UrlReaderServiceBase {
  Future<Either<Failure, String>> fetchReadableText(String url);

  /// Returns the FIRST http/https URL found in arbitrary shared text, or
  /// `null`. Bare domains (`example.com/x`) get an `https://` prefix.
  static String? extractUrl(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;

    final schemes = RegExp(
      r'https?://[^\s<>"\x27]+',
      caseSensitive: false,
    ).allMatches(text);
    for (final match in schemes) {
      final candidate = _trimUrlTail(match.group(0) ?? '');
      if (isUrl(candidate)) return candidate;
    }

    final bareDomains = RegExp(
      r'(?:^|(?<=[\s(\[{]))(?:www\.)?[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?'
      r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?)+'
      r'(?:/[^\s<>"\x27]*)?'
      r'(?::\d+)?',
    ).allMatches(text);
    for (final match in bareDomains) {
      final candidate = _trimUrlTail(match.group(0) ?? '');
      if (candidate.isEmpty) continue;
      final prefixed = 'https://$candidate';
      if (isUrl(prefixed)) return prefixed;
    }

    return null;
  }

  static String _trimUrlTail(String value) {
    var result = value.trim();
    while (result.isNotEmpty && '.,;:!?)]}\'"'.contains(result[result.length - 1])) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  /// Whether [value] is an absolute http/https URL with a host.
  static bool isUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return false;
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    final scheme = uri.scheme.toLowerCase();
    if (!uri.hasScheme || (scheme != 'http' && scheme != 'https')) return false;
    return uri.host.isNotEmpty;
  }

  /// Returns `null` when [url] is acceptable, else a short human message.
  static String? validateUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return 'URL is empty';
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return 'URL is missing a host';
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return 'Unsupported URL scheme: ${uri.scheme}';
    }
    if (uri.host.isEmpty) return 'URL is missing a host';
    return null;
  }
}
