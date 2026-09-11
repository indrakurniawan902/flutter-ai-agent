import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:flutter_ai_agent/features/server_profiles/data/models/server_profile_model.dart';
import 'package:flutter_ai_agent/features/server_profiles/domain/entities/server_profile.dart';
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

/// Service wrapping FlutterSecureStorage to securely persist LLM endpoint configurations and server profiles.
class SecureStorageService {
  static const String keyBaseUrl = 'llm_base_url';
  static const String keyApiKey = 'llm_api_key';
  static const String keyModel = 'llm_model';
  static const String keyTemperature = 'llm_temperature';
  static const String keyServerProfiles = 'server_profiles_list';

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

  /// Retrieves the list of saved [ServerProfile] configurations.
  Future<List<ServerProfile>> getServerProfiles() async {
    final raw = await _storage.read(key: keyServerProfiles);
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded.map((item) {
        if (item is Map<String, dynamic>) {
          return ServerProfileModel.fromJson(item);
        } else if (item is Map) {
          return ServerProfileModel.fromJson(Map<String, dynamic>.from(item));
        }
        throw const FormatException('Invalid item in profiles list');
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// Serializes and writes a list of [ServerProfile]s to secure storage.
  Future<void> saveServerProfiles(List<ServerProfile> profiles) async {
    final list = profiles
        .map((p) => ServerProfileModel.fromEntity(p).toJson())
        .toList();
    await _storage.write(key: keyServerProfiles, value: jsonEncode(list));
  }

  /// Finds a [ServerProfile] by its unique [id].
  Future<ServerProfile?> getServerProfileById(String id) async {
    final profiles = await getServerProfiles();
    try {
      return profiles.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Adds a new [ServerProfile] or updates an existing one with matching ID.
  ///
  /// If the saved profile is marked [isActive], all other profiles are deactivated.
  Future<void> saveServerProfile(ServerProfile profile) async {
    final profiles = await getServerProfiles();
    final updatedList = <ServerProfile>[];
    bool found = false;

    for (final p in profiles) {
      if (p.id == profile.id) {
        updatedList.add(profile);
        found = true;
      } else {
        if (profile.isActive) {
          updatedList.add(p.copyWith(isActive: false));
        } else {
          updatedList.add(p);
        }
      }
    }

    if (!found) {
      if (profile.isActive) {
        final deactivated =
            updatedList.map((p) => p.copyWith(isActive: false)).toList();
        deactivated.add(profile);
        await saveServerProfiles(deactivated);
        return;
      } else {
        updatedList.add(profile);
      }
    }

    await saveServerProfiles(updatedList);
  }

  /// Deletes a [ServerProfile] with the given [id] from secure storage.
  Future<void> deleteServerProfile(String id) async {
    final profiles = await getServerProfiles();
    final filtered = profiles.where((p) => p.id != id).toList();
    await saveServerProfiles(filtered);
  }

  /// Retrieves the currently active [ServerProfile], if any.
  Future<ServerProfile?> getActiveServerProfile() async {
    final profiles = await getServerProfiles();
    try {
      return profiles.firstWhere((p) => p.isActive);
    } catch (_) {
      return null;
    }
  }

  /// Activates the [ServerProfile] with [id] and deactivates all other profiles.
  ///
  /// When [syncSettings] is true (default), synchronizes the profile's gateway URL
  /// and token into [keyBaseUrl] and [keyApiKey].
  Future<void> setActiveServerProfile(
    String id, {
    bool syncSettings = true,
  }) async {
    final profiles = await getServerProfiles();
    ServerProfile? active;
    final updated = profiles.map((p) {
      if (p.id == id) {
        final newActive = p.copyWith(isActive: true);
        active = newActive;
        return newActive;
      }
      return p.copyWith(isActive: false);
    }).toList();

    await saveServerProfiles(updated);

    if (syncSettings && active != null) {
      await Future.wait([
        saveBaseUrl(active!.gatewayUrl),
        saveApiKey(active!.token),
      ]);
    }
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
