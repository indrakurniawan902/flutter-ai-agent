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
  ///
  /// The host is canonicalised (lowercased, all trailing dots stripped)
  /// before inspection, so `localhost.`, `127.0.0.1.`, and every IPv6
  /// spelling of a private address cannot slip past the checks.
  ///
  /// Residual risk: a hostname that resolves to private space through
  /// wildcard DNS without embedding a literal address (for example
  /// `internal.example.com` pointing at 10.0.0.5) cannot be detected here.
  /// DNS resolution is deliberately not performed in this pure, synchronous
  /// domain helper.
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

  /// Lowercases [host] and strips every trailing dot, so `LOCALHOST.` and
  /// `127.0.0.1.` compare as their canonical spellings. A bracketed IPv6
  /// host such as `[::1].` canonicalises to `[::1]`.
  static String canonicaliseHost(String host) {
    var normalised = host.toLowerCase();
    while (normalised.endsWith('.')) {
      normalised = normalised.substring(0, normalised.length - 1);
    }
    return normalised;
  }

  /// Whether [host] is loopback, link-local, or inside a private range.
  ///
  /// Pure address inspection only; no DNS resolution happens here.
  static bool isDisallowedHost(String host) {
    final normalised = canonicaliseHost(host);
    if (normalised.isEmpty) return true;
    if (normalised == 'localhost' ||
        normalised.endsWith('.localhost') ||
        normalised.endsWith('.local')) {
      return true;
    }
    if (_isDisallowedIpv6(normalised)) return true;
    final octets = _parseIpv4(normalised);
    if (octets != null) return _isDisallowedIpv4(octets);
    return isResolvablePrivateHost(normalised);
  }

  /// Whether [host] embeds a private IPv4 literal in four consecutive
  /// labels, as wildcard-DNS services such as `127.0.0.1.nip.io` do, or in
  /// four hyphen-joined labels, as `127-0-0-1.nip.io` does.
  ///
  /// This is a pure, synchronous heuristic; no DNS resolution happens
  /// here. A hostname that resolves to private space without embedding a
  /// literal address cannot be detected in the domain layer, which is a
  /// documented residual risk.
  static bool isResolvablePrivateHost(String host) {
    final normalised = canonicaliseHost(host);
    final labels = normalised.split('.');
    for (var i = 0; i + 4 <= labels.length; i++) {
      final octets = _parseIpv4(labels.sublist(i, i + 4).join('.'));
      if (octets != null && _isDisallowedIpv4(octets)) return true;
    }
    for (final label in labels) {
      final octets = _parseIpv4Parts(label.split('-'));
      if (octets != null && _isDisallowedIpv4(octets)) return true;
    }
    return false;
  }

  /// Whether [host] is an IPv6 address that reaches loopback, unspecified,
  /// IPv4-mapped/translated, IPv4-compatible, link-local, unique-local,
  /// 6to4, or NAT64 space.
  ///
  /// Every comparison runs on the parsed 16-bit groups, so uppercase hex,
  /// expanded spellings, and a trailing zone id (`fe80::1%25eth0`) do not
  /// bypass the checks.
  static bool _isDisallowedIpv6(String host) {
    final groups = _parseIpv6(host);
    if (groups == null) return false;
    if (_leadingZeroGroups(groups) == 8) return true;
    final mapped = _mappedIpv4(groups);
    if (mapped != null) return _isDisallowedIpv4(mapped);
    if ((groups[0] & 0xffc0) == 0xfe80) return true;
    if ((groups[0] & 0xfe00) == 0xfc00) return true;
    if (groups[0] == 0x2002) {
      return _isDisallowedIpv4(_ipv4FromGroups(groups[1], groups[2]));
    }
    if (groups[0] == 0x0064 &&
        groups[1] == 0xff9b &&
        groups[2] == 0 &&
        groups[3] == 0 &&
        groups[4] == 0 &&
        groups[5] == 0) {
      return _isDisallowedIpv4(_ipv4FromGroups(groups[6], groups[7]));
    }
    if (_leadingZeroGroups(groups) >= 6) {
      return _isDisallowedIpv4(_ipv4FromGroups(groups[6], groups[7]));
    }
    return false;
  }

  /// Returns the embedded IPv4 address when [groups] has the IPv4-mapped
  /// shape of RFC 4291 2.2.3.1: an `0xffff` group preceded only by zeros,
  /// followed only by zero groups before the 32-bit address at the end.
  /// Returns null for any other address.
  static List<int>? _mappedIpv4(List<int> groups) {
    var marker = -1;
    for (var i = 0; i <= 5; i++) {
      if (groups[i] == 0) continue;
      if (groups[i] != 0xffff) return null;
      marker = i;
      break;
    }
    if (marker < 0) return null;
    for (var i = marker + 1; i < groups.length - 2; i++) {
      if (groups[i] != 0) return null;
    }
    return _ipv4FromGroups(groups[6], groups[7]);
  }

  /// Parses [host] as an IPv6 address into eight 16-bit groups, accepting
  /// both the expanded and the `::`-compressed spelling plus a trailing
  /// IPv4 tail such as `::ffff:127.0.0.1`. Returns null when [host] is not
  /// an IPv6 address.
  static List<int>? _parseIpv6(String host) {
    var text = host;
    if (text.startsWith('[') && text.endsWith(']')) {
      text = text.substring(1, text.length - 1);
    }
    final zone = text.indexOf('%');
    if (zone >= 0) {
      text = text.substring(0, zone);
    }
    if (!text.contains(':')) return null;
    final lastColon = text.lastIndexOf(':');
    if (text.substring(lastColon + 1).contains('.')) {
      final octets = _parseIpv4(text.substring(lastColon + 1));
      if (octets == null) return null;
      final high = ((octets[0] << 8) | octets[1]).toRadixString(16);
      final low = ((octets[2] << 8) | octets[3]).toRadixString(16);
      text = '${text.substring(0, lastColon + 1)}$high:$low';
    }
    final parts = text.split('::');
    if (parts.length > 2) return null;
    final head = parts[0].isEmpty ? const <String>[] : parts[0].split(':');
    final tail = parts.length == 2 && parts[1].isNotEmpty
        ? parts[1].split(':')
        : const <String>[];
    final explicit = parts.length == 1;
    if (explicit && head.length != 8) return null;
    if (!explicit && head.length + tail.length > 7) return null;
    final filled = <String>[
      ...head,
      if (!explicit) ...List.filled(8 - head.length - tail.length, '0'),
      ...tail,
    ];
    final values = <int>[];
    for (final group in filled) {
      if (group.isEmpty || group.length > 4) return null;
      final value = int.tryParse(group, radix: 16);
      if (value == null) return null;
      values.add(value);
    }
    return values;
  }

  static List<int> _ipv4FromGroups(int high, int low) => [
    high >> 8,
    high & 0xff,
    low >> 8,
    low & 0xff,
  ];

  static int _leadingZeroGroups(List<int> groups) {
    var count = 0;
    while (count < groups.length && groups[count] == 0) {
      count++;
    }
    return count;
  }

  static bool _isDisallowedIpv4(List<int> octets) {
    final first = octets[0];
    final second = octets[1];
    if (first == 0 || first == 10 || first == 127) return true;
    if (first == 100 && second >= 64 && second <= 127) return true;
    if (first == 169 && second == 254) return true;
    if (first == 172 && second >= 16 && second <= 31) return true;
    if (first == 192 && second == 168) return true;
    if (first == 198 && (second == 18 || second == 19)) return true;
    return false;
  }

  static List<int>? _parseIpv4(String host) => _parseIpv4Parts(host.split('.'));

  /// Parses [parts] as four decimal octets, each 1-3 digits and at most
  /// 255. Returns null when the count or any part is invalid.
  static List<int>? _parseIpv4Parts(List<String> parts) {
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
