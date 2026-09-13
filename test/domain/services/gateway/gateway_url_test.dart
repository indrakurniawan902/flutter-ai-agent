import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_client.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_url.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('acceptedGatewayUrlSchemes', () {
    test('is exactly the four schemes the client can normalize', () {
      // Pinned deliberately: widening the allow-list must fail loudly here so
      // the validator and normalizeGatewayUri cannot silently drift apart.
      expect(acceptedGatewayUrlSchemes, {'http', 'https', 'ws', 'wss'});
    });

    test('shares the bridge default path with GatewayClient', () {
      expect(defaultGatewayPath, '/device/ws');
      expect(GatewayClient.defaultGatewayPath, defaultGatewayPath);
    });
  });

  group('isAcceptableGatewayUrl - accepts', () {
    const accepted = <String>[
      'wss://hermes.indra-developer.my.id/device/ws',
      'https://hermes.indra-developer.my.id',
      'http://192.168.1.10:8644',
      'ws://192.168.1.10:18789/device/ws',
      'ws://example.com/custom',
      'wss://example.com/ws',
      'http://localhost:8080',
      'https://vps.example.com:18789/device/ws',
    ];

    for (final url in accepted) {
      test('accepts $url', () {
        expect(isAcceptableGatewayUrl(url), isTrue);
      });
    }

    test('accepts input surrounded by whitespace', () {
      expect(
        isAcceptableGatewayUrl('  wss://hermes.indra-developer.my.id/device/ws  '),
        isTrue,
      );
    });

    test('accepts a bare host (client appends $defaultGatewayPath)', () {
      expect(isAcceptableGatewayUrl('https://host'), isTrue);
      expect(isAcceptableGatewayUrl('wss://host'), isTrue);
    });
  });

  group('isAcceptableGatewayUrl - rejects', () {
    const rejected = <String>[
      '',
      '   ',
      'not a url',
      'invalid-url',
      'ftp://host',
      'file://host/tmp',
      'httpx://host',
      'wsss://host',
      // Scheme-relative and scheme-less forms: the transport layer would
      // happily prepend ws:// to these, but the UI must not accept them.
      '//host',
      'hermes.indra-developer.my.id/device/ws',
      'localhost:8080',
      'http://',
      'https://',
      'ws://',
      'wss://',
      'http:///device/ws',
    ];

    for (final url in rejected) {
      test('rejects ${url.isEmpty ? '<empty>' : url}', () {
        expect(isAcceptableGatewayUrl(url), isFalse);
      });
    }
  });

  group('isAcceptableGatewayUrl <-> normalizeGatewayUri drift guard', () {
    const inputs = <String>[
      // Accepted
      'wss://hermes.indra-developer.my.id/device/ws',
      'https://hermes.indra-developer.my.id',
      'http://192.168.1.10:8644',
      'ws://192.168.1.10:18789/device/ws',
      '  http://localhost:8080  ',
      'wss://host',
      // Rejected
      '',
      'not a url',
      'invalid-url',
      'ftp://host',
      'httpx://host',
      '//host',
      'hermes.indra-developer.my.id/device/ws',
      'http://',
    ];

    test('every URL the validator admits normalizes to a usable ws(s) URI',
        () {
      for (final input in inputs) {
        if (!isAcceptableGatewayUrl(input)) continue;

        // The whole point of sharing the predicate: anything the form lets the
        // user save must be something the transport can actually dial.
        final normalized = GatewayClient.normalizeGatewayUri(input);

        expect(
          normalized.scheme == 'ws' || normalized.scheme == 'wss',
          isTrue,
          reason: '"$input" normalized to ${normalized.scheme}',
        );
        expect(normalized.host.isNotEmpty, isTrue, reason: '"$input"');
        expect(
          normalized.path.isNotEmpty && normalized.path != '/',
          isTrue,
          reason: '"$input" lost its path',
        );
      }
    });

    test('the predicate is stricter than the transport layer', () {
      // normalizeGatewayUri deliberately prepends ws:// to anything, so a
      // rejected scheme-less string still yields a parseable URI. That is
      // expected: the validator exists precisely to keep such guesses out of
      // the saved profile. What must never happen is the reverse - a URL the
      // validator admits that the client cannot dial (covered above).
      expect(isAcceptableGatewayUrl('example.com:18789'), isFalse);
      expect(
        GatewayClient.normalizeGatewayUri('example.com:18789').toString(),
        'ws://example.com:18789/device/ws',
      );
    });

    test('uppercase schemes are admitted and normalize correctly', () {
      // Schemes are case-insensitive (RFC 3986), so the predicate admits them -
      // and normalizeGatewayUri must keep agreeing instead of mis-parsing
      // `WSS://host` into a garbage `ws://wss` authority.
      expect(isAcceptableGatewayUrl('WSS://host'), isTrue);
      expect(isAcceptableGatewayUrl('HTTP://192.168.1.10:8644'), isTrue);
      expect(
        GatewayClient.normalizeGatewayUri('WSS://host').toString(),
        'wss://host/device/ws',
      );
      expect(
        GatewayClient.normalizeGatewayUri('HTTP://192.168.1.10:8644').toString(),
        'ws://192.168.1.10:8644/device/ws',
      );
    });
  });
}
