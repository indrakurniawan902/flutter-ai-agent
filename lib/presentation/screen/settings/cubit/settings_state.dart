import 'package:equatable/equatable.dart';

/// Base state for SettingsCubit.
sealed class SettingsState extends Equatable {
  final String baseUrl;
  final String apiKey;
  final String model;
  final double temperature;

  const SettingsState({
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.temperature = 0.7,
  });

  @override
  List<Object?> get props => [baseUrl, apiKey, model, temperature];
}

/// Initial state before any settings load is triggered.
class SettingsInitial extends SettingsState {
  const SettingsInitial({
    super.baseUrl,
    super.apiKey,
    super.model,
    super.temperature,
  });
}

/// Loading saved settings from secure storage.
class SettingsLoading extends SettingsState {
  const SettingsLoading({
    super.baseUrl,
    super.apiKey,
    super.model,
    super.temperature,
  });
}

/// Settings loaded and ready to be viewed/edited.
class SettingsLoaded extends SettingsState {
  const SettingsLoaded({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
    required super.temperature,
  });
}

/// Saving settings into secure storage.
class SettingsSaving extends SettingsState {
  const SettingsSaving({
    required super.baseUrl,
    required super.apiKey,
    required super.model,
    required super.temperature,
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
    this.message = 'Settings saved successfully',
  });

  @override
  List<Object?> get props => [baseUrl, apiKey, model, temperature, message];
}

/// An error occurred during load, validation, or save.
class SettingsError extends SettingsState {
  final String message;

  const SettingsError({
    super.baseUrl,
    super.apiKey,
    super.model,
    super.temperature,
    required this.message,
  });

  @override
  List<Object?> get props => [baseUrl, apiKey, model, temperature, message];
}
