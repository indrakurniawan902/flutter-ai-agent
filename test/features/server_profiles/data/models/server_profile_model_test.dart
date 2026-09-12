import 'package:flutter_ai_agent/core/constants/constants.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/features/server_profiles/data/models/server_profile_model.dart';
import 'package:flutter_ai_agent/features/server_profiles/domain/entities/server_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final testDate = DateTime.utc(2026, 9, 11, 10, 0, 0);

  final tServerProfile = ServerProfile(
    id: 'vps-oracle',
    name: 'VPS Oracle',
    gatewayUrl: 'https://indra-9router.my.id/v1',
    token: 'sk-test-token-123',
    isActive: true,
    lastConnected: testDate,
    model: AppConstants.defaultModel,
    temperature: AppConstants.defaultTemperature,
  );

  group('ServerProfile Entity', () {
    test('supports value equality', () {
      final profile1 = ServerProfile(
        id: '1',
        name: 'Dev Server',
        gatewayUrl: 'http://localhost:8080',
        token: 'token-1',
        isActive: false,
        lastConnected: testDate,
      );

      final profile2 = ServerProfile(
        id: '1',
        name: 'Dev Server',
        gatewayUrl: 'http://localhost:8080',
        token: 'token-1',
        isActive: false,
        lastConnected: testDate,
      );

      expect(profile1, equals(profile2));
    });

    test('copyWith copies and overrides fields', () {
      final updated = tServerProfile.copyWith(
        name: 'Oracle Cloud',
        isActive: false,
      );

      expect(updated.id, 'vps-oracle');
      expect(updated.name, 'Oracle Cloud');
      expect(updated.gatewayUrl, 'https://indra-9router.my.id/v1');
      expect(updated.token, 'sk-test-token-123');
      expect(updated.isActive, isFalse);
      expect(updated.lastConnected, testDate);
    });

    test('copyWith can clear lastConnected when clearLastConnected is true', () {
      final updated = tServerProfile.copyWith(
        clearLastConnected: true,
      );

      expect(updated.lastConnected, isNull);
    });

    test('fromPairingPayload creates ServerProfile from PairingPayload', () {
      final payload = PairingPayload(
        gatewayUrl: 'https://gateway.example.com',
        token: 'token-pair-123',
        profileName: 'MacBook Pro Local',
        timestamp: testDate,
      );

      final profile = ServerProfile.fromPairingPayload(
        payload,
        id: 'mbp-local',
        isActive: true,
      );

      expect(profile.id, 'mbp-local');
      expect(profile.name, 'MacBook Pro Local');
      expect(profile.gatewayUrl, 'https://gateway.example.com');
      expect(profile.token, 'token-pair-123');
      expect(profile.isActive, isTrue);
    });
  });

  group('ServerProfileModel', () {
    test('is a subclass of ServerProfile entity', () {
      final model = ServerProfileModel(
        id: '1',
        name: 'Test',
        gatewayUrl: 'https://test.com',
        token: 'tok',
      );

      expect(model, isA<ServerProfile>());
    });

    test('fromJson parses camelCase JSON with ISO-8601 date', () {
      final json = {
        'id': 'vps-oracle',
        'name': 'VPS Oracle',
        'gatewayUrl': 'https://indra-9router.my.id/v1',
        'token': 'sk-test-token-123',
        'isActive': true,
        'lastConnected': testDate.toIso8601String(),
        'model': 'ag-glm',
        'temperature': 0.7,
      };

      final result = ServerProfileModel.fromJson(json);

      expect(result.id, 'vps-oracle');
      expect(result.name, 'VPS Oracle');
      expect(result.gatewayUrl, 'https://indra-9router.my.id/v1');
      expect(result.token, 'sk-test-token-123');
      expect(result.isActive, isTrue);
      expect(result.lastConnected, testDate);
      expect(result.model, 'ag-glm');
      expect(result.temperature, 0.7);
    });

    test('fromJson parses snake_case JSON with integer millis timestamp', () {
      final json = {
        'id': 'vps-oracle',
        'name': 'VPS Oracle',
        'gateway_url': 'https://indra-9router.my.id/v1',
        'token': 'sk-test-token-123',
        'is_active': true,
        'last_connected': testDate.millisecondsSinceEpoch,
      };

      final result = ServerProfileModel.fromJson(json);

      expect(result.id, 'vps-oracle');
      expect(result.name, 'VPS Oracle');
      expect(result.gatewayUrl, 'https://indra-9router.my.id/v1');
      expect(result.token, 'sk-test-token-123');
      expect(result.isActive, isTrue);
      expect(result.lastConnected, testDate);
    });

    test('fromJson parses integer seconds timestamp', () {
      final seconds = testDate.millisecondsSinceEpoch ~/ 1000;
      final json = {
        'id': 'vps-oracle',
        'name': 'VPS Oracle',
        'gatewayUrl': 'https://indra-9router.my.id/v1',
        'token': 'sk-test-token-123',
        'isActive': false,
        'lastConnected': seconds,
      };

      final result = ServerProfileModel.fromJson(json);

      expect(result.lastConnected?.millisecondsSinceEpoch, seconds * 1000);
      expect(result.isActive, isFalse);
    });

    test('fromJson handles null or missing optional fields gracefully', () {
      final json = {
        'name': 'Dev Server',
      };

      final result = ServerProfileModel.fromJson(json);

      expect(result.name, 'Dev Server');
      expect(result.gatewayUrl, '');
      expect(result.token, '');
      expect(result.isActive, isFalse);
      expect(result.lastConnected, isNull);
      expect(result.model, AppConstants.defaultModel);
      expect(result.temperature, AppConstants.defaultTemperature);
    });

    test('fromJson applies defaults when model is missing or empty', () {
      final missing = ServerProfileModel.fromJson({'name': 'A'});
      expect(missing.model, AppConstants.defaultModel);

      final empty = ServerProfileModel.fromJson({'name': 'A', 'model': '  '});
      expect(empty.model, AppConstants.defaultModel);
    });

    test('fromJson parses custom model and numeric/string temperature', () {
      final numeric = ServerProfileModel.fromJson({
        'name': 'A',
        'model': 'custom-model',
        'temperature': 0.3,
      });
      expect(numeric.model, 'custom-model');
      expect(numeric.temperature, 0.3);

      final fromString = ServerProfileModel.fromJson({
        'name': 'A',
        'temperature': '0.9',
      });
      expect(fromString.temperature, 0.9);

      final invalidString = ServerProfileModel.fromJson({
        'name': 'A',
        'temperature': 'not-a-number',
      });
      expect(invalidString.temperature, AppConstants.defaultTemperature);
    });

    test('toJson produces correct JSON map', () {
      final model = ServerProfileModel.fromEntity(tServerProfile);
      final json = model.toJson();

      expect(json, {
        'id': 'vps-oracle',
        'name': 'VPS Oracle',
        'gatewayUrl': 'https://indra-9router.my.id/v1',
        'token': 'sk-test-token-123',
        'isActive': true,
        'lastConnected': testDate.toIso8601String(),
        'model': 'ag-glm',
        'temperature': 0.7,
      });
    });

    test('toJson round-trips custom model and temperature', () {
      final model = ServerProfileModel(
        id: '1',
        name: 'Custom',
        gatewayUrl: 'https://test.com',
        token: 'tok',
        model: 'custom-model',
        temperature: 0.3,
      );

      final restored = ServerProfileModel.fromJson(model.toJson());

      expect(restored.model, 'custom-model');
      expect(restored.temperature, 0.3);
      expect(restored, model);
    });
  });
}
