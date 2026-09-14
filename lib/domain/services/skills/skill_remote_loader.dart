import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

/// Fetches raw SKILL.md documents from remote URLs.
abstract class SkillRemoteLoaderBase {
  /// Fetches a raw SKILL.md document.
  Future<Either<Failure, String>> fetchSkillMarkdown(String url);

  /// Returns null when [url] is acceptable, else a short human message.
  /// Accepts only absolute https URLs whose host is a public name or
  /// address; loopback, link-local, and private-range hosts are refused to
  /// keep the fetch inside the trust boundary.
  static String? validateSourceUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return 'URL is empty';
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return 'URL is missing a host';
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https') {
      return 'Unsupported URL scheme: ${uri.scheme}';
    }
    final host = uri.host.toLowerCase();
    if (host.isEmpty) return 'URL is missing a host';
    if (isDisallowedHost(host)) return 'URL host is not allowed: ${uri.host}';
    return null;
  }

  /// Whether [host] is loopback, link-local, or inside a private range.
  static bool isDisallowedHost(String host) {
    final normalised = host.toLowerCase();
    if (normalised.isEmpty) return true;
    if (normalised == 'localhost' ||
        normalised.endsWith('.localhost') ||
        normalised.endsWith('.local')) {
      return true;
    }
    if (normalised == '::1' || normalised == '[::1]') return true;
    final octets = _parseIpv4(normalised);
    if (octets == null) return false;
    final first = octets[0];
    final second = octets[1];
    if (first == 0 || first == 10 || first == 127) return true;
    if (first == 169 && second == 254) return true;
    if (first == 172 && second >= 16 && second <= 31) return true;
    if (first == 192 && second == 168) return true;
    return false;
  }

  static List<int>? _parseIpv4(String host) {
    final parts = host.split('.');
    if (parts.length != 4) return null;
    final octets = <int>[];
    for (final part in parts) {
      if (part.isEmpty || part.length > 3) return null;
      for (final codeUnit in part.codeUnits) {
        if (codeUnit < 0x30 || codeUnit > 0x39) return null;
      }
      final value = int.parse(part);
      if (value > 255) return null;
      octets.add(value);
    }
    return octets;
  }
}
