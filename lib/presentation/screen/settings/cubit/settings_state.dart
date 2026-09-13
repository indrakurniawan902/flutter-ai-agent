import 'package:equatable/equatable.dart';
import 'package:flutter_ai_agent/domain/entities/chat/nfc_tag_prompt_binding.dart';

/// Base state for SettingsCubit.
sealed class SettingsState extends Equatable {
  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;
  final bool progressiveToolPruning;

  const SettingsState({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.temperature = 0.7,
    this.progressiveToolPruning = true,
  });

  @override
  List<Object?> get props =>
      [baseUrl, apiKey, model, temperature, progressiveToolPruning];
}

/// Initial state before any settings load is triggered.
class SettingsInitial extends SettingsState {
  const SettingsInitial({
    super.baseUrl,
    super.apiKey,
    super.model,
    super.temperature,
    super.progressiveToolPruning,
  });
}

/// Loading saved settings from secure storage.
class SettingsLoading extends SettingsState {
  const SettingsLoading({
    super.baseUrl,
    super.apiKey,
    super.model,
    super.temperature,
    super.progressiveToolPruning,
  });
}

/// Settings loaded and ready to be viewed/edited.
class SettingsLoaded extends SettingsState {
  final List<NfcTagPromptBinding> nfcPromptBindings;

  /// Whether the NFC scanning service is available in this session.
  final bool nfcAvailable;

  const SettingsLoaded({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
    required super.temperature,
    super.progressiveToolPruning,
    this.nfcPromptBindings = const [],
    this.nfcAvailable = false,
  });

  SettingsLoaded copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    double? temperature,
    bool? progressiveToolPruning,
    List<NfcTagPromptBinding>? nfcPromptBindings,
    bool? nfcAvailable,
  }) =>
      SettingsLoaded(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        temperature: temperature ?? this.temperature,
        progressiveToolPruning: progressiveToolPruning ?? this.progressiveToolPruning,
        nfcPromptBindings: nfcPromptBindings ?? this.nfcPromptBindings,
        nfcAvailable: nfcAvailable ?? this.nfcAvailable,
      );

  @override
  List<Object?> get props => [
        baseUrl,
        apiKey,
        model,
        temperature,
        progressiveToolPruning,
        nfcPromptBindings,
        nfcAvailable,
      ];
}

/// Saving settings into secure storage.
class SettingsSaving extends SettingsState {
  const SettingsSaving({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
    required super.temperature,
    super.progressiveToolPruning,
  });
}

/// Settings saved successfully into secure storage.
class SettingsSuccess extends SettingsState {
  final String message;

  const SettingsSuccess({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
    required super.temperature,
    super.progressiveToolPruning,
    this.message = 'Settings saved successfully',
  });

  @override
  List<Object?> get props =>
      [baseUrl, apiKey, model, temperature, progressiveToolPruning, message];
}

/// NFC tag UID captured, waiting for the user to confirm prompt/label.
class SettingsNfcScanResult extends SettingsLoaded {
  final String uid;

  const SettingsNfcScanResult({
    required this.uid,
    super.baseUrl = '',
    super.apiKey = '',
    super.model = '',
    super.temperature = 0.7,
    super.progressiveToolPruning = true,
    super.nfcPromptBindings = const [],
    super.nfcAvailable = false,
  });

  @override
  List<Object?> get props => [
        uid,
        baseUrl,
        apiKey,
        model,
        temperature,
        progressiveToolPruning,
        nfcPromptBindings,
        nfcAvailable,
      ];
}

/// An error occurred during load, validation, or save.
class SettingsError extends SettingsState {
  final String message;

  const SettingsError({
    super.baseUrl,
    super.apiKey,
    super.model,
    super.temperature,
    super.progressiveToolPruning,
    required this.message,
  });

  @override
  List<Object?> get props =>
      [baseUrl, apiKey, model, temperature, progressiveToolPruning, message];
}
