import 'package:equatable/equatable.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Holds a snapshot of saved LLM settings.
class SettingsData extends Equatable {
  final String? baseUrl;
  final String? apiKey;
  final String? model;
  final double? temperature;

  const SettingsData({
    this.baseUrl,
    this.apiKey,
    this.model,
    this.temperature,
  });

  @override
  List<Object?> get props => [baseUrl, apiKey, model, temperature];
}

/// Service wrapping FlutterSecureStorage to securely persist LLM endpoint configurations.
class SecureStorageService {
  static const String keyBaseUrl = 'llm_base_url';
  static const String keyApiKey = 'llm_api_key';
  static const String keyModel = 'llm_model';
  static const String keyTemperature = 'llm_temperature';

  final FlutterSecureStorage _storage;

  SecureStorageService({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveBaseUrl(String baseUrl) async {
    await _storage.write(key: keyBaseUrl, value: baseUrl);
  }

  Future<String?> getBaseUrl() async {
    return _storage.read(key: keyBaseUrl);
  }

  Future<void> saveApiKey(String apiKey) async {
    await _storage.write(key: keyApiKey, value: apiKey);
  }

  Future<String?> getApiKey() async {
    return _storage.read(key: keyApiKey);
  }

  Future<void> saveModel(String model) async {
    await _storage.write(key: keyModel, value: model);
  }

  Future<String?> getModel() async {
    return _storage.read(key: keyModel);
  }

  Future<void> saveTemperature(double temperature) async {
    await _storage.write(key: keyTemperature, value: temperature.toString());
  }

  Future<double?> getTemperature() async {
    final value = await _storage.read(key: keyTemperature);
    if (value == null) return null;
    return double.tryParse(value);
  }

  Future<void> saveSettings({
    required String baseUrl,
    required String apiKey,
    required String model,
    required double temperature,
  }) async {
    await Future.wait([
      saveBaseUrl(baseUrl),
      saveApiKey(apiKey),
      saveModel(model),
      saveTemperature(temperature),
    ]);
  }

  Future<SettingsData> getSettings() async {
    final results = await Future.wait([
      getBaseUrl(),
      getApiKey(),
      getModel(),
      getTemperature(),
    ]);

    return SettingsData(
      baseUrl: results[0] as String?,
      apiKey: results[1] as String?,
      model: results[2] as String?,
      temperature: results[3] as double?,
    );
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
