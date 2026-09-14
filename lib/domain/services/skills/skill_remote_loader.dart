import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

/// Fetches raw SKILL.md documents from remote URLs.
abstract class SkillRemoteLoaderBase {
  /// Fetches a raw SKILL.md document.
  Future<Either<Failure, String>> fetchSkillMarkdown(String url);

  /// Returns null when [url] is acceptable, else a short human message.
  /// Accepts only absolute http/https URLs with a non-empty host.
  static String? validateSourceUrl(String url) {
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
