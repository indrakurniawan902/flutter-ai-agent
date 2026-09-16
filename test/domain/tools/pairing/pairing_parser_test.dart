import 'dart:convert';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/pairing_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PairingParser', () {
    late PairingParser parser;
    final testNow = DateTime.parse('2026-09-11T08:10:00.000Z');

    setUp(() {
      parser = const PairingParser();
    });

    group('Positive Cases', () {
      test('successfully parses valid JSON pairing payload with camelCase keys', () {
        final rawJson = jsonEncode({
          'gatewayUrl': 'https://vps.example.com:18789',
          'token': 'secret-token-abc',
          'profileName': 'Remote Node Hermes',
          'timestamp': '2026-09-11T08:05:00.000Z',
        });

        final result = parser.parse(rawJson, currentTime: testNow);

        expect(result.isRight(), isTrue);
        result.fold(
          (failure) => fail('Should succeed: ${failure.message}'),
          (payload) {
            expect(payload.gatewayUrl, 'https://vps.example.com:18789');
            expect(payload.token, 'secret-token-abc');
            expect(payload.profileName, 'Remote Node Hermes');
            expect(
              payload.timestamp,
              DateTime.parse('2026-09-11T08:05:00.000Z'),
            );
          },
        );
      });

      test('successfully parses valid JSON pairing payload with snake_case keys', () {
        final rawJson = jsonEncode({
          'gateway_url': 'http://192.168.1.50:18789',
          'token': 'local-token-xyz',
          'profile_name': 'MacBook Local',
          'timestamp': testNow.subtract(const Duration(minutes: 2)).millisecondsSinceEpoch,
        });

        final result = parser.parse(rawJson, currentTime: testNow);

        expect(result.isRight(), isTrue);
        result.fold(
          (failure) => fail('Should succeed: ${failure.message}'),
          (payload) {
            expect(payload.gatewayUrl, 'http://192.168.1.50:18789');
            expect(payload.token, 'local-token-xyz');
            expect(payload.profileName, 'MacBook Local');
          },
        );
      });

      test('trims whitespace and handles raw string gracefully', () {
        final rawJson = '   \n{"gatewayUrl":"https://test.com","token":"t1","profileName":"P1","timestamp":"2026-09-11T08:09:00.000Z"}  \n ';

        final result = parser.parse(rawJson, currentTime: testNow);

        expect(result.isRight(), isTrue);
      });
    });

    group('Negative Cases: Malformed JSON', () {
      test('returns ParseFailure for completely non-JSON string', () {
        const rawString = 'this is just random qr text, not json';

        final result = parser.parse(rawString, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, contains('Malformed JSON'));
          },
          (_) => fail('Should fail on non-JSON'),
        );
      });

      test('returns ParseFailure for truncated or corrupted JSON', () {
        const corruptedJson = '{"gatewayUrl": "https://test.com", "token": ';

        final result = parser.parse(corruptedJson, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, contains('Malformed JSON'));
          },
          (_) => fail('Should fail on corrupted JSON'),
        );
      });

      test('returns ParseFailure if JSON root is a list, not an object', () {
        const listJson = '["gatewayUrl", "token"]';

        final result = parser.parse(listJson, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, contains('JSON object'));
          },
          (_) => fail('Should fail when root is not a Map'),
        );
      });
    });

    group('Negative Cases: Invalid QR Payload', () {
      test('returns ParseFailure when gatewayUrl is missing', () {
        final json = jsonEncode({
          'token': 'secret-token-abc',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, contains('gatewayUrl is required'));
          },
          (_) => fail('Should fail when gatewayUrl is missing'),
        );
      });

      test('returns ParseFailure when gatewayUrl is not a valid HTTP/HTTPS URL', () {
        final json = jsonEncode({
          'gatewayUrl': 'not_a_valid_url',
          'token': 'secret-token-abc',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, contains('valid HTTP/HTTPS'));
          },
          (_) => fail('Should fail when URL scheme is invalid'),
        );
      });

      test('returns ParseFailure when token is empty or missing', () {
        final json = jsonEncode({
          'gatewayUrl': 'https://gateway.example.com',
          'token': '   ',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, contains('token is required'));
          },
          (_) => fail('Should fail when token is empty'),
        );
      });

      test('returns ParseFailure when profileName is empty or missing', () {
        final json = jsonEncode({
          'gatewayUrl': 'https://gateway.example.com',
          'token': 'valid-token',
          'profileName': '',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, contains('profileName is required'));
          },
          (_) => fail('Should fail when profileName is empty'),
        );
      });
    });

    group('Negative Cases: Destination Confusion', () {
      test('rejects a payload URL carrying a dotted user-info segment', () {
        final json = jsonEncode({
          'gatewayUrl': 'https://trusted.example@pair.evil.example:8443',
          'token': 'secret-token-abc',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, contains('user-info'));
          },
          (_) => fail('Should fail when URL carries user-info'),
        );
      });

      test('rejects user-info on an otherwise-private host', () {
        final json = jsonEncode({
          'gatewayUrl': 'http://pair.evil.example@192.168.1.50:18789',
          'token': 'secret-token-abc',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, contains('user-info'));
          },
          (_) => fail('Should fail when private host URL carries user-info'),
        );
      });

      test('rejects plaintext to a public host', () {
        final json = jsonEncode({
          'gatewayUrl': 'http://pair.evil.example:18789',
          'token': 'secret-token-abc',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, contains('plaintext'));
          },
          (_) => fail('Should fail when plaintext targets a public host'),
        );
      });

      test('accepts https to a public host (user confirmation is the control)', () {
        final json = jsonEncode({
          'gatewayUrl': 'https://pair.evil.example:8443',
          'token': 'secret-token-abc',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isRight(), isTrue);
      });

      test('accepts the plaintext LAN URL', () {
        final json = jsonEncode({
          'gatewayUrl': 'http://192.168.1.50:18789',
          'token': 'secret-token-abc',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isRight(), isTrue);
      });

      test('accepts plaintext to 10.0.0.7 port 18789', () {
        final json = jsonEncode({
          'gatewayUrl': 'http://10.0.0.7:18789',
          'token': 'secret-token-abc',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isRight(), isTrue);
      });

      test('accepts plaintext to localhost port 18789', () {
        final json = jsonEncode({
          'gatewayUrl': 'http://localhost:18789',
          'token': 'secret-token-abc',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isRight(), isTrue);
      });

      test('returns ParseFailure without throwing for an oversized port on https', () {
        final json = jsonEncode({
          'gatewayUrl': 'https://pair.evil.example:99999999999999999999',
          'token': 'secret-token-abc',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<ParseFailure>()),
          (_) => fail('Should fail on an oversized port'),
        );
      });

      test('returns ParseFailure without throwing for an oversized port on a plaintext private host', () {
        final json = jsonEncode({
          'gatewayUrl': 'http://192.168.1.50:99999999999999999999',
          'token': 'secret-token-abc',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) => expect(failure, isA<ParseFailure>()),
          (_) => fail('Should fail on an oversized port'),
        );
      });

      test('rejects an empty host without skipping the transport policy', () {
        final json = jsonEncode({
          'gatewayUrl': 'http://',
          'token': 'secret-token-abc',
          'profileName': 'Remote Node',
          'timestamp': testNow.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, isNot(contains('valid HTTP/HTTPS')));
          },
          (_) => fail('Should fail when the destination is unresolvable'),
        );
      });
    });

    group('Negative Cases: Expired Token', () {
      test('returns ParseFailure when token has expired based on default maxAge (15 mins)', () {
        final oldTimestamp = testNow.subtract(const Duration(minutes: 16));
        final json = jsonEncode({
          'gatewayUrl': 'https://gateway.example.com',
          'token': 'expired-token',
          'profileName': 'Remote Node',
          'timestamp': oldTimestamp.toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, contains('expired'));
          },
          (_) => fail('Should fail when token is expired'),
        );
      });

      test('returns ParseFailure when explicit expiresAt in the past', () {
        final json = jsonEncode({
          'gatewayUrl': 'https://gateway.example.com',
          'token': 'expired-token',
          'profileName': 'Remote Node',
          'timestamp': testNow.subtract(const Duration(minutes: 5)).toIso8601String(),
          'expiresAt': testNow.subtract(const Duration(seconds: 10)).toIso8601String(),
        });

        final result = parser.parse(json, currentTime: testNow);

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ParseFailure>());
            expect(failure.message, contains('expired'));
          },
          (_) => fail('Should fail when expiresAt is in past'),
        );
      });

      test('can disable expiration check via checkExpiration flag', () {
        final oldTimestamp = testNow.subtract(const Duration(minutes: 30));
        final json = jsonEncode({
          'gatewayUrl': 'https://gateway.example.com',
          'token': 'expired-token',
          'profileName': 'Remote Node',
          'timestamp': oldTimestamp.toIso8601String(),
        });

        final result = parser.parse(
          json,
          currentTime: testNow,
          checkExpiration: false,
        );

        expect(result.isRight(), isTrue);
      });
    });
  });
}
