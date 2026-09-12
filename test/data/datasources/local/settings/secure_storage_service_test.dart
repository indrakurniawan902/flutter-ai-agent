import 'dart:convert';

import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/data/models/server_profiles/server_profile_model.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_trigger_settings.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

void main() {
  late MockFlutterSecureStorage mockStorage;
  late SecureStorageService service;

  setUp(() {
    mockStorage = MockFlutterSecureStorage();
    service = SecureStorageService(storage: mockStorage);
  });

  group('SecureStorageService - Base URL', () {
    const testBaseUrl = 'https://indra-9router.my.id/v1';

    test('saveBaseUrl writes to storage with key llm_base_url', () async {
      when(() => mockStorage.write(
            key: SecureStorageService.keyBaseUrl,
            value: testBaseUrl,
          )).thenAnswer((_) async {});

      await service.saveBaseUrl(testBaseUrl);

      verify(() => mockStorage.write(
            key: SecureStorageService.keyBaseUrl,
            value: testBaseUrl,
          )).called(1);
    });

    test('getBaseUrl reads from storage with key llm_base_url', () async {
      when(() => mockStorage.read(key: SecureStorageService.keyBaseUrl))
          .thenAnswer((_) async => testBaseUrl);

      final result = await service.getBaseUrl();

      expect(result, testBaseUrl);
      verify(() => mockStorage.read(key: SecureStorageService.keyBaseUrl)).called(1);
    });

    test('getBaseUrl returns null when key does not exist', () async {
      when(() => mockStorage.read(key: SecureStorageService.keyBaseUrl))
          .thenAnswer((_) async => null);

      final result = await service.getBaseUrl();

      expect(result, isNull);
    });
  });

  group('SecureStorageService - API Key', () {
    const testApiKey = 'sk-test-secret-key-12345';

    test('saveApiKey writes to storage with key llm_api_key', () async {
      when(() => mockStorage.write(
            key: SecureStorageService.keyApiKey,
            value: testApiKey,
          )).thenAnswer((_) async {});

      await service.saveApiKey(testApiKey);

      verify(() => mockStorage.write(
            key: SecureStorageService.keyApiKey,
            value: testApiKey,
          )).called(1);
    });

    test('getApiKey reads from storage with key llm_api_key', () async {
      when(() => mockStorage.read(key: SecureStorageService.keyApiKey))
          .thenAnswer((_) async => testApiKey);

      final result = await service.getApiKey();

      expect(result, testApiKey);
      verify(() => mockStorage.read(key: SecureStorageService.keyApiKey)).called(1);
    });
  });

  group('SecureStorageService - Model', () {
    const testModel = 'ag-glm';

    test('saveModel writes to storage with key llm_model', () async {
      when(() => mockStorage.write(
            key: SecureStorageService.keyModel,
            value: testModel,
          )).thenAnswer((_) async {});

      await service.saveModel(testModel);

      verify(() => mockStorage.write(
            key: SecureStorageService.keyModel,
            value: testModel,
          )).called(1);
    });

    test('getModel reads from storage with key llm_model', () async {
      when(() => mockStorage.read(key: SecureStorageService.keyModel))
          .thenAnswer((_) async => testModel);

      final result = await service.getModel();

      expect(result, testModel);
      verify(() => mockStorage.read(key: SecureStorageService.keyModel)).called(1);
    });
  });

  group('SecureStorageService - Temperature', () {
    const testTemperature = 0.7;

    test('saveTemperature writes to storage as string with key llm_temperature', () async {
      when(() => mockStorage.write(
            key: SecureStorageService.keyTemperature,
            value: '0.7',
          )).thenAnswer((_) async {});

      await service.saveTemperature(testTemperature);

      verify(() => mockStorage.write(
            key: SecureStorageService.keyTemperature,
            value: '0.7',
          )).called(1);
    });

    test('getTemperature parses string from storage to double', () async {
      when(() => mockStorage.read(key: SecureStorageService.keyTemperature))
          .thenAnswer((_) async => '0.7');

      final result = await service.getTemperature();

      expect(result, 0.7);
    });

    test('getTemperature returns null when key does not exist', () async {
      when(() => mockStorage.read(key: SecureStorageService.keyTemperature))
          .thenAnswer((_) async => null);

      final result = await service.getTemperature();

      expect(result, isNull);
    });

    test('getTemperature returns null when storage value is invalid double', () async {
      when(() => mockStorage.read(key: SecureStorageService.keyTemperature))
          .thenAnswer((_) async => 'not-a-double');

      final result = await service.getTemperature();

      expect(result, isNull);
    });
  });

  group('SecureStorageService - Batch Settings and Clear', () {
    test('saveSettings writes all 4 keys to storage', () async {
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      await service.saveSettings(
        baseUrl: 'https://indra-9router.my.id/v1',
        apiKey: 'sk-12345',
        model: 'ag-glm',
        temperature: 0.5,
      );

      verify(() => mockStorage.write(
            key: SecureStorageService.keyBaseUrl,
            value: 'https://indra-9router.my.id/v1',
          )).called(1);
      verify(() => mockStorage.write(
            key: SecureStorageService.keyApiKey,
            value: 'sk-12345',
          )).called(1);
      verify(() => mockStorage.write(
            key: SecureStorageService.keyModel,
            value: 'ag-glm',
          )).called(1);
      verify(() => mockStorage.write(
            key: SecureStorageService.keyTemperature,
            value: '0.5',
          )).called(1);
    });

    test('getSettings retrieves all settings in a SettingsData bundle', () async {
      when(() => mockStorage.read(key: SecureStorageService.keyBaseUrl))
          .thenAnswer((_) async => 'https://indra-9router.my.id/v1');
      when(() => mockStorage.read(key: SecureStorageService.keyApiKey))
          .thenAnswer((_) async => 'sk-12345');
      when(() => mockStorage.read(key: SecureStorageService.keyModel))
          .thenAnswer((_) async => 'ag-glm');
      when(() => mockStorage.read(key: SecureStorageService.keyTemperature))
          .thenAnswer((_) async => '0.8');
      when(() => mockStorage.read(
              key: SecureStorageService.keyProgressiveToolPruning))
          .thenAnswer((_) async => 'true');

      final settings = await service.getSettings();

      expect(settings.baseUrl, 'https://indra-9router.my.id/v1');
      expect(settings.apiKey, 'sk-12345');
      expect(settings.model, 'ag-glm');
      expect(settings.temperature, 0.8);
      expect(settings.progressiveToolPruning, true);
    });

    test('clearAll delegates to deleteAll on storage', () async {
      when(() => mockStorage.deleteAll()).thenAnswer((_) async {});

      await service.clearAll();

      verify(() => mockStorage.deleteAll()).called(1);
    });
  });

  group('SecureStorageService - Server Profiles CRUD', () {
    final profile1 = ServerProfile(
      id: 'profile-1',
      name: 'VPS Oracle',
      gatewayUrl: 'https://indra-9router.my.id/v1',
      token: 'sk-token-1',
      isActive: true,
      lastConnected: DateTime.utc(2026, 9, 11, 10, 0),
    );

    final profile2 = ServerProfile(
      id: 'profile-2',
      name: 'Dev Server',
      gatewayUrl: 'http://localhost:8080',
      token: 'sk-token-2',
      isActive: false,
    );

    test('getServerProfiles returns empty list when key does not exist or empty', () async {
      when(() => mockStorage.read(key: SecureStorageService.keyServerProfiles))
          .thenAnswer((_) async => null);

      final result = await service.getServerProfiles();

      expect(result, isEmpty);
    });

    test('getServerProfiles returns empty list on invalid/corrupt JSON', () async {
      when(() => mockStorage.read(key: SecureStorageService.keyServerProfiles))
          .thenAnswer((_) async => '{not valid json list');

      final result = await service.getServerProfiles();

      expect(result, isEmpty);
    });

    test('getServerProfiles returns parsed profiles on valid JSON', () async {
      final jsonString = jsonEncode([
        ServerProfileModel.fromEntity(profile1).toJson(),
        ServerProfileModel.fromEntity(profile2).toJson(),
      ]);

      when(() => mockStorage.read(key: SecureStorageService.keyServerProfiles))
          .thenAnswer((_) async => jsonString);

      final result = await service.getServerProfiles();

      expect(result.length, 2);
      expect(result[0], equals(profile1));
      expect(result[1], equals(profile2));
    });

    test('saveServerProfiles serializes and writes to storage', () async {
      when(() => mockStorage.write(
            key: SecureStorageService.keyServerProfiles,
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      await service.saveServerProfiles([profile1, profile2]);

      verify(() => mockStorage.write(
            key: SecureStorageService.keyServerProfiles,
            value: any(that: contains('VPS Oracle'), named: 'value'),
          )).called(1);
    });

    test('getServerProfileById returns matching profile or null', () async {
      final jsonString = jsonEncode([
        ServerProfileModel.fromEntity(profile1).toJson(),
      ]);
      when(() => mockStorage.read(key: SecureStorageService.keyServerProfiles))
          .thenAnswer((_) async => jsonString);

      final found = await service.getServerProfileById('profile-1');
      final notFound = await service.getServerProfileById('non-existent');

      expect(found, equals(profile1));
      expect(notFound, isNull);
    });

    test('saveServerProfile adds new profile and deactivates others if active', () async {
      final initialJson = jsonEncode([
        ServerProfileModel.fromEntity(profile1).toJson(), // isActive = true
      ]);

      when(() => mockStorage.read(key: SecureStorageService.keyServerProfiles))
          .thenAnswer((_) async => initialJson);
      when(() => mockStorage.write(
            key: SecureStorageService.keyServerProfiles,
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      final newActiveProfile = ServerProfile(
        id: 'profile-3',
        name: 'MacBook Pro',
        gatewayUrl: 'https://mbp.local',
        token: 'sk-mbp',
        isActive: true,
      );

      await service.saveServerProfile(newActiveProfile);

      final captured = verify(() => mockStorage.write(
            key: SecureStorageService.keyServerProfiles,
            value: captureAny(named: 'value'),
          )).captured;

      final savedList = (jsonDecode(captured.first as String) as List)
          .map((m) => ServerProfileModel.fromJson(m as Map<String, dynamic>))
          .toList();

      expect(savedList.length, 2);
      expect(savedList.firstWhere((p) => p.id == 'profile-1').isActive, isFalse);
      expect(savedList.firstWhere((p) => p.id == 'profile-3').isActive, isTrue);
    });

    test('saveServerProfile updates existing profile', () async {
      final initialJson = jsonEncode([
        ServerProfileModel.fromEntity(profile1).toJson(),
      ]);

      when(() => mockStorage.read(key: SecureStorageService.keyServerProfiles))
          .thenAnswer((_) async => initialJson);
      when(() => mockStorage.write(
            key: SecureStorageService.keyServerProfiles,
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      final updated = profile1.copyWith(name: 'Renamed VPS');
      await service.saveServerProfile(updated);

      final captured = verify(() => mockStorage.write(
            key: SecureStorageService.keyServerProfiles,
            value: captureAny(named: 'value'),
          )).captured;

      final savedList = (jsonDecode(captured.first as String) as List)
          .map((m) => ServerProfileModel.fromJson(m as Map<String, dynamic>))
          .toList();

      expect(savedList.length, 1);
      expect(savedList.first.name, 'Renamed VPS');
    });

    test('deleteServerProfile removes profile by id', () async {
      final initialJson = jsonEncode([
        ServerProfileModel.fromEntity(profile1).toJson(),
        ServerProfileModel.fromEntity(profile2).toJson(),
      ]);

      when(() => mockStorage.read(key: SecureStorageService.keyServerProfiles))
          .thenAnswer((_) async => initialJson);
      when(() => mockStorage.write(
            key: SecureStorageService.keyServerProfiles,
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      await service.deleteServerProfile('profile-1');

      final captured = verify(() => mockStorage.write(
            key: SecureStorageService.keyServerProfiles,
            value: captureAny(named: 'value'),
          )).captured;

      final savedList = (jsonDecode(captured.first as String) as List)
          .map((m) => ServerProfileModel.fromJson(m as Map<String, dynamic>))
          .toList();

      expect(savedList.length, 1);
      expect(savedList.first.id, 'profile-2');
    });

    test('getActiveServerProfile returns the active profile', () async {
      final jsonString = jsonEncode([
        ServerProfileModel.fromEntity(profile1).toJson(), // active
        ServerProfileModel.fromEntity(profile2).toJson(), // inactive
      ]);

      when(() => mockStorage.read(key: SecureStorageService.keyServerProfiles))
          .thenAnswer((_) async => jsonString);

      final active = await service.getActiveServerProfile();

      expect(active, equals(profile1));
    });

    test('setActiveServerProfile activates target, deactivates others, and syncs settings by default', () async {
      final jsonString = jsonEncode([
        ServerProfileModel.fromEntity(profile1).toJson(), // active
        ServerProfileModel.fromEntity(profile2).toJson(), // inactive
      ]);

      when(() => mockStorage.read(key: SecureStorageService.keyServerProfiles))
          .thenAnswer((_) async => jsonString);
      when(() => mockStorage.write(
            key: any(named: 'key'),
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      await service.setActiveServerProfile('profile-2', syncSettings: true);

      // Verify server profiles storage write
      verify(() => mockStorage.write(
            key: SecureStorageService.keyServerProfiles,
            value: any(named: 'value'),
          )).called(1);

      // Verify sync to llm_base_url and llm_api_key
      verify(() => mockStorage.write(
            key: SecureStorageService.keyBaseUrl,
            value: 'http://localhost:8080',
          )).called(1);
      verify(() => mockStorage.write(
            key: SecureStorageService.keyApiKey,
            value: 'sk-token-2',
          )).called(1);
      verify(() => mockStorage.write(
            key: SecureStorageService.keyModel,
            value: profile2.model,
          )).called(1);
      verify(() => mockStorage.write(
            key: SecureStorageService.keyTemperature,
            value: profile2.temperature.toString(),
          )).called(1);
    });
  });

  group('SecureStorageService - Ambient Trigger Settings', () {
    test(
        'getAmbientTriggerSettings returns default const AmbientTriggerSettings() when key is null or empty',
        () async {
      when(() => mockStorage.read(
              key: SecureStorageService.keyAmbientTriggerSettings))
          .thenAnswer((_) async => null);

      final resultNull = await service.getAmbientTriggerSettings();
      expect(resultNull, const AmbientTriggerSettings());

      when(() => mockStorage.read(
              key: SecureStorageService.keyAmbientTriggerSettings))
          .thenAnswer((_) async => '');

      final resultEmpty = await service.getAmbientTriggerSettings();
      expect(resultEmpty, const AmbientTriggerSettings());

      when(() => mockStorage.read(
              key: SecureStorageService.keyAmbientTriggerSettings))
          .thenAnswer((_) async => '   ');

      final resultWhitespace = await service.getAmbientTriggerSettings();
      expect(resultWhitespace, const AmbientTriggerSettings());
    });

    test('getAmbientTriggerSettings returns default when JSON is malformed',
        () async {
      when(() => mockStorage.read(
              key: SecureStorageService.keyAmbientTriggerSettings))
          .thenAnswer((_) async => '{not valid json');

      final result = await service.getAmbientTriggerSettings();
      expect(result, const AmbientTriggerSettings());
    });

    test(
        'getAmbientTriggerSettings returns parsed AmbientTriggerSettings when valid JSON is stored',
        () async {
      const settings = AmbientTriggerSettings(
        geofenceEnabled: false,
        batteryWatchdogEnabled: true,
        notificationListenerEnabled: false,
        heartbeatEnabled: true,
      );
      final jsonString = jsonEncode(settings.toJson());

      when(() => mockStorage.read(
              key: SecureStorageService.keyAmbientTriggerSettings))
          .thenAnswer((_) async => jsonString);

      final result = await service.getAmbientTriggerSettings();
      expect(result, equals(settings));
      expect(result.geofenceEnabled, isFalse);
      expect(result.batteryWatchdogEnabled, isTrue);
      expect(result.notificationListenerEnabled, isFalse);
      expect(result.heartbeatEnabled, isTrue);
    });

    test(
        'saveAmbientTriggerSettings serializes and writes JSON to SecureStorageService.keyAmbientTriggerSettings',
        () async {
      const settings = AmbientTriggerSettings(
        geofenceEnabled: false,
        batteryWatchdogEnabled: false,
        notificationListenerEnabled: true,
        heartbeatEnabled: false,
      );

      when(() => mockStorage.write(
            key: SecureStorageService.keyAmbientTriggerSettings,
            value: any(named: 'value'),
          )).thenAnswer((_) async {});

      await service.saveAmbientTriggerSettings(settings);

      verify(() => mockStorage.write(
            key: SecureStorageService.keyAmbientTriggerSettings,
            value: jsonEncode(settings.toJson()),
          )).called(1);
    });
  });
}
