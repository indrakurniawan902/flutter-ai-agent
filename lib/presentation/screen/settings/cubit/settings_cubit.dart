import 'package:flutter_ai_agent/common/constant.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
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
      progressiveToolPruning: state.progressiveToolPruning,
    ));

    try {
      final baseUrl = await _storageService.getBaseUrl() ?? AppConstants.defaultBaseUrl;
      final apiKey = await _storageService.getApiKey() ?? '';
      final model = await _storageService.getModel() ?? AppConstants.defaultModel;
      final temperature = await _storageService.getTemperature() ?? AppConstants.defaultTemperature;
      final progressiveToolPruning = await _storageService.getProgressiveToolPruning();

      emit(SettingsLoaded(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        temperature: temperature,
        progressiveToolPruning: progressiveToolPruning,
      ));
    } catch (e) {
      emit(SettingsError(
        message: 'Failed to load settings: ${e.toString()}',
        baseUrl: state.baseUrl,
        apiKey: state.apiKey,
        model: state.model,
        temperature: state.temperature,
        progressiveToolPruning: state.progressiveToolPruning,
      ));
    }
  }

  /// Validates and securely saves LLM endpoint configuration.
  Future<bool> saveSettings({
    required String baseUrl,
    required String apiKey,
    required String model,
    required double temperature,
    bool progressiveToolPruning = true,
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
        progressiveToolPruning: progressiveToolPruning,
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
        progressiveToolPruning: progressiveToolPruning,
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
      progressiveToolPruning: progressiveToolPruning,
    ));

    try {
      await _storageService.saveSettings(
        baseUrl: trimmedUrl,
        apiKey: trimmedApiKey,
        model: model.trim(),
        temperature: clampedTemp,
        progressiveToolPruning: progressiveToolPruning,
      );

      emit(SettingsSuccess(
        baseUrl: trimmedUrl,
        apiKey: trimmedApiKey,
        model: model.trim(),
        temperature: clampedTemp,
        progressiveToolPruning: progressiveToolPruning,
        message: 'Settings saved successfully',
      ));
      return true;
    } catch (e) {
      emit(SettingsError(
        baseUrl: trimmedUrl,
        apiKey: trimmedApiKey,
        model: model.trim(),
        temperature: clampedTemp,
        progressiveToolPruning: progressiveToolPruning,
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
      await _storageService.saveProgressiveToolPruning(true);
      if (!preserveApiKey) {
        await _storageService.saveApiKey('');
      }

      emit(SettingsLoaded(
        baseUrl: AppConstants.defaultBaseUrl,
        apiKey: key,
        model: AppConstants.defaultModel,
        temperature: AppConstants.defaultTemperature,
        progressiveToolPruning: true,
      ));
    } catch (e) {
      emit(SettingsError(
        baseUrl: state.baseUrl,
        apiKey: state.apiKey,
        model: state.model,
        temperature: state.temperature,
        progressiveToolPruning: state.progressiveToolPruning,
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
      progressiveToolPruning: state.progressiveToolPruning,
    ));
  }
}
