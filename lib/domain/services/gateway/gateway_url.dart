/// Single source of truth for what counts as a gateway URL.
///
/// A Hermes Gateway endpoint is a WebSocket endpoint, so both the HTTP family
/// (`http`/`https`) and the WebSocket family (`ws`/`wss`) are accepted. The UI
/// validator and the data-layer client both consult this predicate, which keeps
/// them from drifting apart: a URL the form admits must be one
/// `GatewayClient.normalizeGatewayUri` can rewrite into a usable `ws://` /
/// `wss://` URI.
///
/// Pure Dart on purpose - the presentation layer must not depend on `lib/data`,
/// so the shared contract lives here in the domain layer.
library;

/// Schemes [normalizeGatewayUri] can rewrite into a WebSocket URI.
const Set<String> acceptedGatewayUrlSchemes = {'http', 'https', 'ws', 'wss'};

/// Default bridge route the client appends when the URL carries no path.
const String defaultGatewayPath = '/device/ws';

/// Matches a leading URL scheme such as `wss://` and captures the scheme name.
///
/// `Uri.tryParse('not a url')` happily succeeds as a path-only URI, so the
/// scheme is matched explicitly and checked against
/// [acceptedGatewayUrlSchemes] before any parsing happens.
final RegExp _schemePattern = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*)://');

/// Whether [rawUrl] is a gateway URL this client can actually connect to.
///
/// Semantics, in order:
/// 1. [rawUrl] is trimmed; empty or whitespace-only input is rejected.
/// 2. The scheme is matched explicitly and must be one of
///    [acceptedGatewayUrlSchemes] (case-insensitively). Anything without a
///    scheme, with a scheme-relative `//host` form, or with an unsupported
///    scheme (`ftp`, `file`, `httpx`, ...) is rejected.
/// 3. `Uri.tryParse` must succeed and yield a non-empty host.
///
/// A bare host with no path is valid - the client appends
/// [defaultGatewayPath].
bool isAcceptableGatewayUrl(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return false;

  final match = _schemePattern.firstMatch(trimmed);
  if (match == null) return false;
  final scheme = match.group(1)!.toLowerCase();
  if (!acceptedGatewayUrlSchemes.contains(scheme)) return false;

  final uri = Uri.tryParse(trimmed);
  if (uri == null) return false;
  if (uri.host.isEmpty) return false;

  return true;
}
