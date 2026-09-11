import 'package:flutter_ai_agent/features/pairing/data/models/pairing_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PairingPayload', () {
    final testTimestamp = DateTime.parse('2026-09-11T08:00:00.000Z');

    test('instantiates with required properties and supports equality', () {
      final payload1 = PairingPayload(
        gatewayUrl: 'https://gateway.example.com',
        token: 'secret_token_123',
        profileName: 'VPS Oracle',
        timestamp: testTimestamp,
      );

      final payload2 = PairingPayload(
        gatewayUrl: 'https://gateway.example.com',
        token: 'secret_token_123',
        profileName: 'VPS Oracle',
        timestamp: testTimestamp,
      );

      expect(payload1, equals(payload2));
      expect(payload1.gatewayUrl, 'https://gateway.example.com');
      expect(payload1.token, 'secret_token_123');
      expect(payload1.profileName, 'VPS Oracle');
      expect(payload1.timestamp, testTimestamp);
    });

    test('fromJson parses camelCase format with ISO timestamp string', () {
      final json = {
        'gatewayUrl': 'http://192.168.1.100:18789',
        'token': 'tok_abc',
        'profileName': 'MacBook Pro',
        'timestamp': '2026-09-11T08:00:00.000Z',
      };

      final payload = PairingPayload.fromJson(json);

      expect(payload.gatewayUrl, 'http://192.168.1.100:18789');
      expect(payload.token, 'tok_abc');
      expect(payload.profileName, 'MacBook Pro');
      expect(payload.timestamp, testTimestamp);
    });

    test('fromJson parses snake_case format with integer timestamp (millis)', () {
      final json = {
        'gateway_url': 'http://192.168.1.100:18789',
        'token': 'tok_abc',
        'profile_name': 'MacBook Pro',
        'timestamp': testTimestamp.millisecondsSinceEpoch,
      };

      final payload = PairingPayload.fromJson(json);

      expect(payload.gatewayUrl, 'http://192.168.1.100:18789');
      expect(payload.token, 'tok_abc');
      expect(payload.profileName, 'MacBook Pro');
      expect(payload.timestamp, testTimestamp);
    });

    test('fromJson parses integer timestamp in seconds (Unix epoch)', () {
      final json = {
        'gatewayUrl': 'http://192.168.1.100:18789',
        'token': 'tok_abc',
        'profileName': 'MacBook Pro',
        'timestamp': 1789118400, // seconds
      };

      final payload = PairingPayload.fromJson(json);

      expect(payload.timestamp, DateTime.fromMillisecondsSinceEpoch(1789118400 * 1000, isUtc: true));
    });

    test('toJson produces camelCase map with ISO timestamp', () {
      final payload = PairingPayload(
        gatewayUrl: 'https://gateway.example.com',
        token: 'secret_token_123',
        profileName: 'VPS Oracle',
        timestamp: testTimestamp,
      );

      final json = payload.toJson();

      expect(json, {
        'gatewayUrl': 'https://gateway.example.com',
        'token': 'secret_token_123',
        'profileName': 'VPS Oracle',
        'timestamp': testTimestamp.toIso8601String(),
        'expiresAt': null,
      });
    });

    test('isExpired returns false when payload is within maxAge window', () {
      final payload = PairingPayload(
        gatewayUrl: 'https://gateway.example.com',
        token: 'secret_token_123',
        profileName: 'VPS Oracle',
        timestamp: testTimestamp,
      );

      final now = testTimestamp.add(const Duration(minutes: 5));
      expect(payload.isExpired(currentTime: now), isFalse);
    });

    test('isExpired returns true when payload timestamp is older than maxAge', () {
      final payload = PairingPayload(
        gatewayUrl: 'https://gateway.example.com',
        token: 'secret_token_123',
        profileName: 'VPS Oracle',
        timestamp: testTimestamp,
      );

      final now = testTimestamp.add(const Duration(minutes: 16));
      expect(payload.isExpired(currentTime: now), isTrue);
    });

    test('isExpired respects explicit expiresAt field if present', () {
      final expiresAt = testTimestamp.add(const Duration(minutes: 30));
      final payload = PairingPayload(
        gatewayUrl: 'https://gateway.example.com',
        token: 'secret_token_123',
        profileName: 'VPS Oracle',
        timestamp: testTimestamp,
        expiresAt: expiresAt,
      );

      final beforeExpiry = testTimestamp.add(const Duration(minutes: 20));
      final afterExpiry = testTimestamp.add(const Duration(minutes: 31));

      expect(payload.isExpired(currentTime: beforeExpiry), isFalse);
      expect(payload.isExpired(currentTime: afterExpiry), isTrue);
    });
  });
}
