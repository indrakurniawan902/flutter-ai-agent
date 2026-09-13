import 'package:flutter_ai_agent/common/constant.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/nfc_tag_prompt_binding.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

/// Manages LLM settings state, loads persisted credentials on init, and validates inputs.
@injectable
class SettingsCubit extends Cubit<SettingsState> {
  final SecureStorageService _storageService;
  final NfcServiceBase? _nfcService;

  @factoryMethod
  factory SettingsCubit.create({
    required SecureStorageService secureStorageService,
    NfcServiceBase? nfcService,
  }) =>
      SettingsCubit(
        secureStorageService: secureStorageService,
        nfcService: nfcService ??
            (getIt.isRegistered<NfcServiceBase>()
                ? getIt<NfcServiceBase>()
                : null),
      );

  SettingsCubit({
    required SecureStorageService secureStorageService,
    NfcServiceBase? nfcService,
    bool autoLoad = true,
  })  : _storageService = secureStorageService,
        _nfcService = nfcService,
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
      List<NfcTagPromptBinding> nfcPromptBindings = const [];
      try {
        nfcPromptBindings = await _storageService.getNfcPromptBindings();
      } catch (_) {
        nfcPromptBindings = const [];
      }

      emit(SettingsLoaded(
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: model,
        temperature: temperature,
        progressiveToolPruning: progressiveToolPruning,
        nfcPromptBindings: nfcPromptBindings,
        nfcAvailable: _nfcService != null,
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

  /// Persists [bindings] and mirrors them into the loaded state.
  Future<void> saveNfcPromptBindings(List<NfcTagPromptBinding> bindings) async {
    await _storageService.saveNfcPromptBindings(bindings);
    final current = state;
    emit(SettingsLoaded(
      baseUrl: current.baseUrl,
      apiKey: current.apiKey,
      model: current.model,
      temperature: current.temperature,
      progressiveToolPruning: current.progressiveToolPruning,
      nfcPromptBindings: bindings,
      nfcAvailable: current is SettingsLoaded
          ? current.nfcAvailable
          : (_nfcService != null),
    ));
  }

  /// Adds [binding], replacing any existing binding for the same card UID.
  Future<void> addNfcPromptBinding(NfcTagPromptBinding binding) async {
    final state = this.state;
    final List<NfcTagPromptBinding> existingBindings;
    if (state is SettingsNfcScanResult) {
      existingBindings = state.nfcPromptBindings;
    } else if (state is SettingsLoaded) {
      existingBindings = state.nfcPromptBindings;
    } else {
      existingBindings = const [];
    }
    final current = List<NfcTagPromptBinding>.from(existingBindings);
    final existing = current.indexWhere((b) => b.cardUid == binding.cardUid);
    if (existing >= 0) {
      current[existing] = binding;
    } else {
      current.add(binding);
    }
    await saveNfcPromptBindings(current);
  }

  /// Removes the binding for [cardUid], if any.
  Future<void> removeNfcPromptBinding(String cardUid) async {
    final state = this.state;
    final List<NfcTagPromptBinding> existingBindings;
    if (state is SettingsNfcScanResult) {
      existingBindings = state.nfcPromptBindings;
    } else if (state is SettingsLoaded) {
      existingBindings = state.nfcPromptBindings;
    } else {
      existingBindings = const [];
    }
    final current = existingBindings
        .where((b) => b.cardUid != cardUid)
        .toList();
    await saveNfcPromptBindings(current);
  }

  /// Reads the NFC card UID and emits [SettingsNfcScanResult] so the UI can
  /// prompt for the prompt/label pair, confirmed via [confirmNfcPromptBinding].
  Future<void> scanAndBindNfcTag() async {
    final nfc = _nfcService;
    if (nfc == null) {
      _emitNfcScanFailure('NFC service unavailable');
      return;
    }

    final availableResult = await nfc.isAvailable();
    final isAvailable = availableResult.getOrElse(() => false);
    if (!isAvailable) {
      final msg = availableResult.fold(
        (failure) => failure.message,
        (_) => 'NFC is not supported on this device',
      );
      _emitNfcScanFailure(msg);
      return;
    }

    final enabledResult = await nfc.isEnabled();
    final isEnabled = enabledResult.getOrElse(() => false);
    if (!isEnabled) {
      final msg = enabledResult.fold(
        (failure) => failure.message,
        (_) => 'NFC is disabled. Please enable it in system settings.',
      );
      _emitNfcScanFailure(msg);
      return;
    }

    final result = await nfc.readCardUid();
    result.fold(
      (failure) => _emitNfcScanFailure(failure.message),
      (uid) {
        final current = state;
        emit(SettingsNfcScanResult(
          uid: uid,
          baseUrl: current.baseUrl,
          apiKey: current.apiKey,
          model: current.model,
          temperature: current.temperature,
          progressiveToolPruning: current.progressiveToolPruning,
          nfcPromptBindings: current is SettingsLoaded
              ? current.nfcPromptBindings
              : const [],
          nfcAvailable: current is SettingsLoaded
              ? current.nfcAvailable
              : true,
        ));
      },
    );
  }

  /// Confirms a scanned UID by persisting the prompt/label pair.
  Future<void> confirmNfcPromptBinding(
    String uid,
    String prompt, {
    String? label,
  }) async {
    final trimmedLabel = label?.trim();
    await addNfcPromptBinding(NfcTagPromptBinding(
      cardUid: uid.trim().toLowerCase(),
      prompt: prompt.trim(),
      label: (trimmedLabel == null || trimmedLabel.isEmpty)
          ? null
          : trimmedLabel,
      createdAt: DateTime.now(),
    ));
  }

  void _emitNfcScanFailure(String message) {
    final current = state;
    emit(SettingsError(
      baseUrl: current.baseUrl,
      apiKey: current.apiKey,
      model: current.model,
      temperature: current.temperature,
      progressiveToolPruning: current.progressiveToolPruning,
      message: message,
    ));
  }
}
