import 'package:flutter_ai_agent/domain/services/gateway/gateway_url.dart';

/// Where a pairing payload URL will actually send the gateway socket.
///
/// Pure Dart on purpose: the presentation layer needs to show the user the
/// real origin before pairing, but must not depend on `lib/data`. The
/// resolution rules mirror `GatewayClient.normalizeGatewayUri` so the
/// confirmation UI can never drift from the transport that opens the socket.
class PairingDestination {
  /// The rewritten WebSocket URI the client will dial, path included.
  final Uri socketUri;

  /// Resolved transport scheme: `ws` or `wss`.
  final String scheme;

  /// Resolved host (the authority after any user-info segment).
  final String host;

  /// Resolved port, defaulted to 80 for `ws` and 443 for `wss`.
  final int port;

  /// Whether [host] is a local-network address.
  final bool isPrivateRange;

  /// Whether the transport is plaintext (`ws`).
  final bool isPlaintext;

  const PairingDestination({
    required this.socketUri,
    required this.scheme,
    required this.host,
    required this.port,
    required this.isPrivateRange,
    required this.isPlaintext,
  });

  /// Origin to display to the user, built from the resolved values.
  ///
  /// Never the raw payload string: a payload may claim one host while the
  /// socket dials another. IPv6 hosts are bracketed so the result is a valid
  /// origin, for example `wss://[::1]:443`.
  String get displayOrigin {
    final formattedHost = host.contains(':') ? '[$host]' : host;
    return '$scheme://$formattedHost:$port';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PairingDestination &&
            other.socketUri == socketUri &&
            other.scheme == scheme &&
            other.host == host &&
            other.port == port &&
            other.isPrivateRange == isPrivateRange &&
            other.isPlaintext == isPlaintext;
  }

  @override
  int get hashCode =>
      Object.hash(socketUri, scheme, host, port, isPrivateRange, isPlaintext);

  @override
  String toString() {
    return 'PairingDestination(socketUri: $socketUri, scheme: $scheme, '
        'host: $host, port: $port, isPrivateRange: $isPrivateRange, '
        'isPlaintext: $isPlaintext)';
  }
}

/// Resolves the WebSocket destination a pairing payload URL will dial.
///
/// Mirrors `GatewayClient.normalizeGatewayUri`:
/// 1. Trim the input.
/// 2. Map the scheme case-insensitively: `http` to `ws`, `https` to `wss`.
///    Any other scheme - including a scheme-less string - returns null.
/// 3. Parse the rewritten string; return null when parsing fails or the host
///    is empty.
/// 4. Port: read from the same `Uri` that supplies the host, so the resolved
///    origin cannot drift from the origin the transport dials. An explicit
///    port inside 1..65535 is kept; a nonsense port (0, negative, oversized,
///    empty) makes the whole destination unresolvable; a genuinely absent
///    port defaults to 80 for `ws` / 443 for `wss`.
/// 5. An empty or `/` path falls back to [defaultGatewayPath].
///
/// Total function: no input string makes it throw; anything the resolver
/// cannot turn into a usable destination yields null.
PairingDestination? resolvePairingDestination(String rawUrl) {
  // Total function: `Uri` members such as `port` and `replace` can throw on
  // attacker-controlled input (for example an oversized port), so any parse
  // surprise degrades to "unresolvable" instead of escaping to the caller.
  try {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty) return null;

    final lower = trimmed.toLowerCase();
    final String rewritten;
    if (lower.startsWith('http://')) {
      rewritten = 'ws://${trimmed.substring(7)}';
    } else if (lower.startsWith('https://')) {
      rewritten = 'wss://${trimmed.substring(8)}';
    } else {
      return null;
    }

    final uri = Uri.tryParse(rewritten);
    if (uri == null || uri.host.isEmpty) return null;

    final scheme = uri.scheme.toLowerCase();
    final isPlaintext = scheme == 'ws';
    final port = _resolvePort(rewritten, uri, isPlaintext: isPlaintext);
    if (port == null) return null;

    final socketUri = (uri.path.isEmpty || uri.path == '/')
        ? uri.replace(path: defaultGatewayPath)
        : uri;

    final host = uri.host;

    return PairingDestination(
      socketUri: socketUri,
      scheme: scheme,
      host: host,
      port: port,
      isPrivateRange: isPrivateRangeHost(host),
      isPlaintext: isPlaintext,
    );
  } catch (_) {
    return null;
  }
}

/// Reads the effective port, or null when the URL carries a nonsense port.
///
/// The port is taken from the same [uri] that supplies the host, so the
/// resolved origin cannot drift from the origin the transport dials. `Uri`
/// silently drops an explicit `:0` and an empty `:` from the authority, so
/// when [Uri.hasPort] is false the authority text is inspected on the same
/// cut `Uri` uses (a backslash terminates the authority too); an explicit
/// zero or empty port text is rejected rather than defaulted. A present but
/// invalid port (0, negative, above 65535, empty, or too large for `int`)
/// makes the destination unresolvable; a genuinely absent port keeps the
/// transport default (80 for `ws`, 443 for `wss`).
int? _resolvePort(String rewritten, Uri uri, {required bool isPlaintext}) {
  final int defaultPort = isPlaintext ? 80 : 443;

  if (uri.hasPort) {
    final int port;
    try {
      port = uri.port;
    } catch (_) {
      return null;
    }
    if (port < 1 || port > 65535) return null;
    return port;
  }

  try {
    final authorityStart = rewritten.indexOf('//') + 2;
    if (authorityStart < 2) return defaultPort;

    var authority = rewritten.substring(authorityStart);
    var cut = authority.length;
    for (final separator in const ['/', '?', '#', '\\']) {
      final index = authority.indexOf(separator);
      if (index >= 0 && index < cut) cut = index;
    }
    authority = authority.substring(0, cut);

    final atIndex = authority.lastIndexOf('@');
    if (atIndex >= 0) authority = authority.substring(atIndex + 1);

    final String portText;
    if (authority.startsWith('[')) {
      final close = authority.indexOf(']');
      if (close < 0) return null;
      final rest = authority.substring(close + 1);
      if (rest.isEmpty) return defaultPort;
      if (!rest.startsWith(':')) return null;
      portText = rest.substring(1);
    } else {
      final colon = authority.lastIndexOf(':');
      if (colon < 0) return defaultPort;
      portText = authority.substring(colon + 1);
    }

    final port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) return null;
    return port;
  } catch (_) {
    return null;
  }
}

/// Whether [host] is a local-network address.
///
/// True for `localhost`, `*.local`, IPv4 loopback / link-local / RFC1918
/// ranges, IPv6 loopback `::1`, and IPv6 link-local `fe80::/10`. Everything
/// else - including malformed addresses - is false.
bool isPrivateRangeHost(String host) {
  final normalized = host.trim().toLowerCase();
  if (normalized.isEmpty) return false;

  if (normalized == 'localhost' || normalized.endsWith('.local')) {
    return true;
  }

  if (normalized.contains(':')) return _isPrivateIpv6(normalized);

  return _isPrivateIpv4(normalized);
}

/// Whether the pairing payload may use plaintext transport.
///
/// Allowed only when [rawUrl] resolves, the transport is plaintext, and the
/// host is on the local network.
bool isPlaintextPairingAllowed(String rawUrl) {
  final destination = resolvePairingDestination(rawUrl);
  return destination != null &&
      destination.isPlaintext &&
      destination.isPrivateRange;
}

bool _isPrivateIpv4(String host) {
  final parts = host.split('.');
  if (parts.length != 4) return false;

  final octets = <int>[];
  for (final part in parts) {
    if (part.isEmpty || part.length > 3) return false;
    final value = int.tryParse(part);
    if (value == null || value > 255) return false;
    octets.add(value);
  }

  final first = octets[0];
  final second = octets[1];

  if (first == 127) return true;
  if (first == 169 && second == 254) return true;
  if (first == 10) return true;
  if (first == 172 && second >= 16 && second <= 31) return true;
  if (first == 192 && second == 168) return true;

  return false;
}

bool _isPrivateIpv6(String host) {
  if (host == '::1') return true;

  final firstHextet = host.split(':').first;
  if (firstHextet.length != 4) return false;

  final value = int.tryParse(firstHextet, radix: 16);
  if (value == null) return false;

  return value >= 0xfe80 && value <= 0xfebf;
}
