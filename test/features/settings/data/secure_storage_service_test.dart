import 'package:flutter_ai_agent/features/settings/data/secure_storage_service.dart';
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

      final settings = await service.getSettings();

      expect(settings.baseUrl, 'https://indra-9router.my.id/v1');
      expect(settings.apiKey, 'sk-12345');
      expect(settings.model, 'ag-glm');
      expect(settings.temperature, 0.8);
    });

    test('clearAll delegates to deleteAll on storage', () async {
      when(() => mockStorage.deleteAll()).thenAnswer((_) async {});

      await service.clearAll();

      verify(() => mockStorage.deleteAll()).called(1);
    });
  });
}
