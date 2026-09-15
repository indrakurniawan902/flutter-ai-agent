import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_client.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_url.dart';
import 'package:flutter_ai_agent/domain/services/gateway/pairing_destination.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolvePairingDestination', () {
    test('resolves the plaintext LAN URL', () {
      final destination = resolvePairingDestination('http://192.168.1.50:18789');

      expect(destination, isNotNull);
      expect(destination!.scheme, 'ws');
      expect(destination.host, '192.168.1.50');
      expect(destination.port, 18789);
      expect(destination.isPlaintext, isTrue);
      expect(destination.isPrivateRange, isTrue);
      expect(destination.displayOrigin, 'ws://192.168.1.50:18789');
    });

    test('resolves https to a public host', () {
      final destination = resolvePairingDestination('https://pair.evil.example');

      expect(destination, isNotNull);
      expect(destination!.scheme, 'wss');
      expect(destination.host, 'pair.evil.example');
      expect(destination.port, 443);
      expect(destination.isPlaintext, isFalse);
      expect(destination.isPrivateRange, isFalse);
      expect(destination.displayOrigin, 'wss://pair.evil.example:443');
    });

    test('resolves a dotted user-info prefix to the real socket host', () {
      final destination = resolvePairingDestination(
        'https://trusted.example@pair.evil.example',
      );

      expect(destination, isNotNull);
      expect(destination!.host, 'pair.evil.example');
      expect(destination.displayOrigin, 'wss://pair.evil.example:443');
    });

    test('defaults port 80 for http and 443 for https', () {
      expect(resolvePairingDestination('http://192.168.1.50')!.port, 80);
      expect(resolvePairingDestination('https://example.com')!.port, 443);
    });

    test('preserves an explicit port', () {
      expect(resolvePairingDestination('https://example.com:8443')!.port, 8443);
    });

    test('returns null without throwing for a port that exceeds int64', () {
      expect(
        resolvePairingDestination(
          'https://pair.evil.example:99999999999999999999',
        ),
        isNull,
      );
      expect(
        resolvePairingDestination(
          'http://192.168.1.50:99999999999999999999',
        ),
        isNull,
      );
    });

    test('returns null without throwing for port 0, 65536 and -1', () {
      expect(resolvePairingDestination('https://example.com:0'), isNull);
      expect(resolvePairingDestination('https://example.com:65536'), isNull);
      expect(resolvePairingDestination('https://example.com:-1'), isNull);
    });

    test('returns null for an empty port text', () {
      expect(resolvePairingDestination('https://example.com:'), isNull);
      expect(resolvePairingDestination('http://192.168.1.50:'), isNull);
    });

    test('appends $defaultGatewayPath when the path is empty', () {
      final destination = resolvePairingDestination('https://example.com');

      expect(destination!.socketUri.path, defaultGatewayPath);
    });

    test('preserves a custom path', () {
      final destination = resolvePairingDestination('https://example.com/custom');

      expect(destination!.socketUri.path, '/custom');
    });

    test('returns null for unsupported or unparseable input', () {
      expect(resolvePairingDestination('ftp://host'), isNull);
      expect(resolvePairingDestination('not a url'), isNull);
      expect(resolvePairingDestination('http://'), isNull);
      expect(resolvePairingDestination('host:18789'), isNull);
    });

    test('brackets an IPv6 host in displayOrigin', () {
      final destination = resolvePairingDestination('https://[::1]:443');

      expect(destination, isNotNull);
      expect(destination!.host, '::1');
      expect(destination.displayOrigin, 'wss://[::1]:443');
    });
  });

  group('resolvePairingDestination - port agrees with the transport', () {
    // A backslash terminates the authority for `Uri` but not for a hand-rolled
    // string scan; reading host and port from different substrings let the
    // dialog show one origin while the socket dialled another. The resolved
    // origin must always equal what `normalizeGatewayUri` actually dials.
    const inputs = <String>[
      r'http://localhost:37409\@evil.invalid',
      r'https://evil.example:31337\@x',
      r'http://192.168.1.50:31337\@evil.example',
      r'https://gw.example.com:8443\@evil.example',
      r'https://evil.example\:31337',
      r'https://evil.com\:8443',
      'http://192.168.1.50:18789',
      'https://example.com:8443',
      'https://example.com',
      'http://10.0.0.7:18789',
    ];

    for (final input in inputs) {
      test('resolved origin matches the dialled origin for $input', () {
        final destination = resolvePairingDestination(input);
        expect(destination, isNotNull, reason: input);

        final dialled = GatewayClient.normalizeGatewayUri(input);
        final expected = dialled.hasPort
            ? '${dialled.scheme}://${dialled.host}:${dialled.port}'
            : '${dialled.scheme}://${dialled.host}:'
                '${dialled.scheme == 'wss' ? 443 : 80}';

        expect(
          '${destination!.scheme}://${destination.host}:${destination.port}',
          expected,
        );
      });
    }
  });

  group('isPrivateRangeHost - private', () {
    const privateHosts = <String>[
      'localhost',
      'LOCALHOST',
      '127.0.0.1',
      '127.9.9.9',
      '10.1.2.3',
      '172.16.0.1',
      '172.31.255.254',
      '192.168.1.50',
      '169.254.10.10',
      '::1',
      'fe80::1',
      'myhost.local',
    ];

    for (final host in privateHosts) {
      test('isPrivateRangeHost($host) is true', () {
        expect(isPrivateRangeHost(host), isTrue);
      });
    }
  });

  group('isPrivateRangeHost - public or malformed', () {
    const publicHosts = <String>[
      '172.32.0.1',
      '11.0.0.1',
      '8.8.8.8',
      '192.169.1.1',
      'pair.evil.example',
      '999.1.1.1',
      '',
      'example.com',
      'fec0::1',
    ];

    for (final host in publicHosts) {
      test('isPrivateRangeHost(${host.isEmpty ? '<empty>' : host}) is false', () {
        expect(isPrivateRangeHost(host), isFalse);
      });
    }
  });

  group('isPlaintextPairingAllowed', () {
    test('is true for the plaintext LAN URL', () {
      expect(
        isPlaintextPairingAllowed('http://192.168.1.50:18789'),
        isTrue,
      );
    });

    test('is false for plaintext to a public host', () {
      expect(
        isPlaintextPairingAllowed('http://pair.evil.example:18789'),
        isFalse,
      );
    });

    test('is false for https to the LAN host', () {
      expect(
        isPlaintextPairingAllowed('https://192.168.1.50:18789'),
        isFalse,
      );
    });

    test('is false for garbage input', () {
      expect(isPlaintextPairingAllowed('not a url'), isFalse);
    });

    test('does not throw and is false for nonsense ports', () {
      expect(
        isPlaintextPairingAllowed(
          'http://192.168.1.50:99999999999999999999',
        ),
        isFalse,
      );
      expect(isPlaintextPairingAllowed('http://192.168.1.50:0'), isFalse);
      expect(isPlaintextPairingAllowed('http://192.168.1.50:65536'), isFalse);
      expect(isPlaintextPairingAllowed('http://192.168.1.50:-1'), isFalse);
    });
  });
}
