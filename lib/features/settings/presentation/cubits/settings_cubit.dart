import 'package:flutter_ai_agent/core/constants/constants.dart';
import 'package:flutter_ai_agent/features/server_profiles/domain/entities/server_profile.dart';
import 'package:flutter_ai_agent/features/settings/data/secure_storage_service.dart';
import 'package:flutter_ai_agent/features/settings/presentation/cubits/settings_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

/// Manages LLM settings state, loads persisted credentials on init, and validates inputs.
@injectable
class SettingsCubit extends Cubit<SettingsState> {
  final SecureStorageService _storageService;

  @factoryMethod
  factory SettingsCubit.create({
    required SecureStorageService secureStorageService,
  }) =>
      SettingsCubit(secureStorageService: secureStorageService);

  SettingsCubit({
    required SecureStorageService secureStorageService,
    bool autoLoad = true,
  })  : _storageService = secureStorageService,
        super(const SettingsInitial()) {
    if (autoLoad) {
      loadSettings();
    }
  }

  /// Loads configuration from secure storage or falls back to defaults.
  Future<void> loadSettings() async {
    emit(SettingsLoading(
      baseUrl: state.baseUrl,
      apiKey: state.apiKey,
      model: state.model,
      temperature: state.temperature,
    ));

    try {
      final baseUrl = await _storageService.getBaseUrl() ?? AppConstants.defaultBaseUrl;
      final apiKey = await _storageService.getApiKey() ?? '';
      final model = await _storageService.getModel() ?? AppConstants.defaultModel;
      final temperature = await _storageService.getTemperature() ?? AppConstants.defaultTemperature;

      emit(SettingsLoaded(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        temperature: temperature,
      ));
    } catch (e) {
      emit(SettingsError(
        message: 'Failed to load settings: ${e.toString()}',
        baseUrl: state.baseUrl,
        apiKey: state.apiKey,
        model: state.model,
        temperature: state.temperature,
      ));
    }
  }

  /// Validates and securely saves LLM endpoint configuration.
  Future<bool> saveSettings({
    required String baseUrl,
    required String apiKey,
    required String model,
    required double temperature,
  }) async {
    final trimmedUrl = baseUrl.trim();
    final uri = Uri.tryParse(trimmedUrl);
    if (trimmedUrl.isEmpty ||
        uri == null ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.host.isEmpty) {
      emit(SettingsError(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        temperature: temperature,
        message: 'Please enter a valid HTTP/HTTPS URL',
      ));
      return false;
    }

    final trimmedApiKey = apiKey.trim();
    if (trimmedApiKey.isEmpty) {
      emit(SettingsError(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        temperature: temperature,
        message: 'API Key cannot be empty',
      ));
      return false;
    }

    final clampedTemp = temperature.clamp(0.0, 2.0);

    emit(SettingsSaving(
      baseUrl: trimmedUrl,
      apiKey: trimmedApiKey,
      model: model.trim(),
      temperature: clampedTemp,
    ));

    try {
      await _storageService.saveSettings(
        baseUrl: trimmedUrl,
        apiKey: trimmedApiKey,
        model: model.trim(),
        temperature: clampedTemp,
      );

      emit(SettingsSuccess(
        baseUrl: trimmedUrl,
        apiKey: trimmedApiKey,
        model: model.trim(),
        temperature: clampedTemp,
        message: 'Settings saved successfully',
      ));
      return true;
    } catch (e) {
      emit(SettingsError(
        baseUrl: trimmedUrl,
        apiKey: trimmedApiKey,
        model: model.trim(),
        temperature: clampedTemp,
        message: 'Failed to save settings: ${e.toString()}',
      ));
      return false;
    }
  }

  /// Resets configuration back to default values.
  /// Preserves the current API key by default so user credentials aren't lost.
  Future<void> resetToDefaults({bool preserveApiKey = true}) async {
    final key = preserveApiKey ? state.apiKey : '';
    try {
      await _storageService.saveBaseUrl(AppConstants.defaultBaseUrl);
      await _storageService.saveModel(AppConstants.defaultModel);
      await _storageService.saveTemperature(AppConstants.defaultTemperature);
      if (!preserveApiKey) {
        await _storageService.saveApiKey('');
      }

      emit(SettingsLoaded(
        baseUrl: AppConstants.defaultBaseUrl,
        apiKey: key,
        model: AppConstants.defaultModel,
        temperature: AppConstants.defaultTemperature,
      ));
    } catch (e) {
      emit(SettingsError(
        baseUrl: state.baseUrl,
        apiKey: state.apiKey,
        model: state.model,
        temperature: state.temperature,
        message: 'Failed to reset settings: ${e.toString()}',
      ));
    }
  }

  /// Syncs settings state from the active server profile.
  void updateFromProfile(ServerProfile profile) {
    emit(SettingsLoaded(
      baseUrl: profile.gatewayUrl,
      apiKey: profile.token,
      model: profile.model,
      temperature: profile.temperature,
    ));
  }
}
