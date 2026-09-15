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
  });
}
