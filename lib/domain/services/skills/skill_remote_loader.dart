import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

// ponytail: same-host redirects only; a same-host DNS-rebind path remains,
// unreachable without attacker-controlled DNS for a host the user typed.

/// Fetches raw SKILL.md documents from remote URLs.
abstract class SkillRemoteLoaderBase {
  /// Fetches a raw SKILL.md document.
  Future<Either<Failure, String>> fetchSkillMarkdown(String url);

  /// Returns null when [url] is acceptable, else a short human message.
  ///
  /// Only the transport shape is validated: an absolute https URL with a host.
  /// Host classification was deliberately removed — a string denylist cannot
  /// cover wildcard DNS (`127-0-0-1.nip.io`) or every IPv6 spelling of a private
  /// address. The LAN-hop risk is closed by the same-host redirect policy in
  /// the data-layer loader instead.
  static String? validateSourceUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return 'URL is empty';
    final uri = Uri.tryParse(trimmed);
    if (uri == null || uri.host.isEmpty) return 'URL is missing a host';
    if (uri.scheme.toLowerCase() != 'https') {
      return 'Unsupported URL scheme: ${uri.scheme}';
    }
    return null;
  }
}
