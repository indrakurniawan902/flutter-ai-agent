import 'package:flutter_ai_agent/data/models/pairing/pairing_payload_model.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testTimestamp = DateTime.parse('2026-09-11T08:00:00.000Z');
  final testExpiresAt = DateTime.parse('2026-09-11T08:15:00.000Z');

  final tPairingPayload = PairingPayload(
    gatewayUrl: 'https://gateway.example.com',
    token: 'secret_token_123',
    profileName: 'Remote Node',
    timestamp: testTimestamp,
    expiresAt: testExpiresAt,
  );

  final tPairingPayloadModel = PairingPayloadModel(
    gatewayUrl: 'https://gateway.example.com',
    token: 'secret_token_123',
    profileName: 'Remote Node',
    timestamp: testTimestamp,
    expiresAt: testExpiresAt,
  );

  group('PairingPayloadModel', () {
    test('is a subclass of PairingPayload entity', () {
      final model = PairingPayloadModel(
        gatewayUrl: 'https://gateway.example.com',
        token: 'token123',
        profileName: 'Test Profile',
        timestamp: testTimestamp,
      );

      expect(model, isA<PairingPayload>());
    });

    group('fromJson', () {
      test('should return a valid model from JSON map (camelCase with ISO string)', () {
        final jsonMap = {
          'gatewayUrl': 'https://gateway.example.com',
          'token': 'secret_token_123',
          'profileName': 'Remote Node',
          'timestamp': '2026-09-11T08:00:00.000Z',
          'expiresAt': '2026-09-11T08:15:00.000Z',
        };

        final result = PairingPayloadModel.fromJson(jsonMap);

        expect(result, tPairingPayloadModel);
      });

      test('should return a valid model from JSON map (snake_case with int timestamp)', () {
        final jsonMap = {
          'gateway_url': 'https://gateway.example.com',
          'token': 'secret_token_123',
          'profile_name': 'Remote Node',
          'timestamp': testTimestamp.millisecondsSinceEpoch,
          'expires_at': testExpiresAt.millisecondsSinceEpoch,
        };

        final result = PairingPayloadModel.fromJson(jsonMap);

        expect(result, tPairingPayloadModel);
      });
    });

    group('toDomain', () {
      test('should convert PairingPayloadModel to PairingPayload domain entity', () {
        final result = tPairingPayloadModel.toDomain();

        expect(result, isA<PairingPayload>());
        expect(result, tPairingPayload);
        expect(result.gatewayUrl, tPairingPayloadModel.gatewayUrl);
        expect(result.token, tPairingPayloadModel.token);
        expect(result.profileName, tPairingPayloadModel.profileName);
        expect(result.timestamp, tPairingPayloadModel.timestamp);
        expect(result.expiresAt, tPairingPayloadModel.expiresAt);
      });
    });

    group('fromDomain', () {
      test('should create PairingPayloadModel from PairingPayload domain entity', () {
        final result = PairingPayloadModel.fromDomain(tPairingPayload);

        expect(result, isA<PairingPayloadModel>());
        expect(result, tPairingPayloadModel);
        expect(result.gatewayUrl, tPairingPayload.gatewayUrl);
        expect(result.token, tPairingPayload.token);
        expect(result.profileName, tPairingPayload.profileName);
        expect(result.timestamp, tPairingPayload.timestamp);
        expect(result.expiresAt, tPairingPayload.expiresAt);
      });
    });

    group('toJson', () {
      test('should return a JSON map containing proper data', () {
        final result = tPairingPayloadModel.toJson();

        final expectedMap = {
          'gatewayUrl': 'https://gateway.example.com',
          'token': 'secret_token_123',
          'profileName': 'Remote Node',
          'timestamp': testTimestamp.toIso8601String(),
          'expiresAt': testExpiresAt.toIso8601String(),
        };
        expect(result, expectedMap);
      });
    });
  });
}
