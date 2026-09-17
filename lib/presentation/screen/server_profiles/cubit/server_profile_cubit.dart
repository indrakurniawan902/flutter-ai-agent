import 'package:flutter_ai_agent/common/constant.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

/// Cubit managing CRUD operations and active switching for [ServerProfile]s.
@injectable
class ServerProfileCubit extends Cubit<ServerProfileState> {
  final SecureStorageService _secureStorageService;

  @factoryMethod
  factory ServerProfileCubit.create({
    required SecureStorageService secureStorageService,
  }) =>
      ServerProfileCubit(secureStorageService: secureStorageService);

  ServerProfileCubit({
    required SecureStorageService secureStorageService,
    bool autoLoad = true,
  })  : _secureStorageService = secureStorageService,
        super(const ServerProfileInitial()) {
    if (autoLoad) {
      loadProfiles();
    }
  }

  /// Loads the server profiles list from secure storage.
  Future<void> loadProfiles() async {
    emit(ServerProfileLoading(
      profiles: state.profiles,
      activeProfile: state.activeProfile,
    ));

    try {
      final profiles = await _secureStorageService.getServerProfiles();
      ServerProfile? active;
      try {
        active = profiles.firstWhere((p) => p.isActive);
      } catch (_) {
        active = null;
      }

      emit(ServerProfileLoaded(
        profiles: profiles,
        activeProfile: active,
      ));
    } catch (e) {
      emit(ServerProfileError(
        profiles: state.profiles,
        activeProfile: state.activeProfile,
        message:
            FailureMessage.humanize(e, context: 'Failed to load server profiles'),
      ));
    }
  }

  /// Adds a new server profile to secure storage.
  ///
  /// Validates [name], [gatewayUrl], and [token].
  /// If this is the first profile being saved or [makeActive] is true,
  /// the profile is automatically marked as active and synced to settings.
  Future<void> addProfile({
    required String name,
    required String gatewayUrl,
    required String token,
    bool makeActive = false,
    String? id,
    String? model,
    double? temperature,
    ServerProfileKind kind = ServerProfileKind.hermesAgent,
  }) async {
    final trimmedName = name.trim();
    final trimmedUrl = gatewayUrl.trim();
    final trimmedToken = token.trim();

    if (trimmedName.isEmpty) {
      emit(ServerProfileError(
        profiles: state.profiles,
        activeProfile: state.activeProfile,
        message: 'Profile name cannot be empty',
      ));
      return;
    }

    if (trimmedUrl.isEmpty) {
      emit(ServerProfileError(
        profiles: state.profiles,
        activeProfile: state.activeProfile,
        message: 'Please enter a valid HTTP/HTTPS URL',
      ));
      return;
    }

    final uri = Uri.tryParse(trimmedUrl);
    if (uri == null ||
        (!uri.isScheme('http') && !uri.isScheme('https')) ||
        uri.host.isEmpty) {
      emit(ServerProfileError(
        profiles: state.profiles,
        activeProfile: state.activeProfile,
        message: 'Please enter a valid HTTP/HTTPS URL',
      ));
      return;
    }

    if (trimmedToken.isEmpty) {
      emit(ServerProfileError(
        profiles: state.profiles,
        activeProfile: state.activeProfile,
        message: 'Authentication token cannot be empty',
      ));
      return;
    }

    emit(ServerProfileLoading(
      profiles: state.profiles,
      activeProfile: state.activeProfile,
    ));

    try {
      final existingProfiles = await _secureStorageService.getServerProfiles();
      final shouldBeActive = makeActive || existingProfiles.isEmpty;

      final newProfile = ServerProfile(
        id: id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        name: trimmedName,
        gatewayUrl: trimmedUrl,
        token: trimmedToken,
        isActive: shouldBeActive,
        model: model ?? AppConstants.defaultModel,
        temperature: temperature ?? AppConstants.defaultTemperature,
        kind: kind,
      );

      await _secureStorageService.saveServerProfile(newProfile);

      if (shouldBeActive) {
        await Future.wait([
          _secureStorageService.saveBaseUrl(trimmedUrl),
          _secureStorageService.saveApiKey(trimmedToken),
          _secureStorageService.saveModel(newProfile.model),
          _secureStorageService.saveTemperature(newProfile.temperature),
        ]);
      }

      final updatedProfiles = await _secureStorageService.getServerProfiles();
      ServerProfile? active;
      try {
        active = updatedProfiles.firstWhere((p) => p.isActive);
      } catch (_) {
        active = null;
      }

      emit(ServerProfileOperationSuccess(
        profiles: updatedProfiles,
        activeProfile: active,
        message: 'Server profile "$trimmedName" added successfully',
      ));
    } catch (e) {
      emit(ServerProfileError(
        profiles: state.profiles,
        activeProfile: state.activeProfile,
        message:
            FailureMessage.humanize(e, context: 'Failed to save server profile'),
      ));
    }
  }

  /// Adds a server profile directly from a scanned [PairingPayload].
  Future<void> addFromPairingPayload(
    PairingPayload payload, {
    bool makeActive = true,
  }) async {
    await addProfile(
      name: payload.profileName.isEmpty ? 'Hermes Gateway' : payload.profileName,
      gatewayUrl: payload.gatewayUrl,
      token: payload.token,
      makeActive: makeActive,
    );
  }

  /// Switches the active server profile to the one with [id].
  ///
  /// Synchronizes the selected profile's URL and token into the settings storage.
  Future<void> switchActiveProfile(String id) async {
    emit(ServerProfileLoading(
      profiles: state.profiles,
      activeProfile: state.activeProfile,
    ));

    try {
      await _secureStorageService.setActiveServerProfile(id, syncSettings: true);

      final updatedProfiles = await _secureStorageService.getServerProfiles();
      final active = updatedProfiles.firstWhere(
        (p) => p.id == id,
        orElse: () => throw Exception('Profile not found'),
      );

      emit(ServerProfileOperationSuccess(
        profiles: updatedProfiles,
        activeProfile: active,
        message: 'Switched to profile "${active.name}"',
      ));
    } catch (e) {
      emit(ServerProfileError(
        profiles: state.profiles,
        activeProfile: state.activeProfile,
        message: FailureMessage.humanize(
            e, context: 'Failed to switch server profile'),
      ));
    }
  }

  /// Updates the currently active profile's editable fields and syncs them to settings storage.
  Future<void> updateActiveProfile({
    String? gatewayUrl,
    String? token,
    String? model,
    double? temperature,
  }) async {
    try {
      final active = await _secureStorageService.getActiveServerProfile();
      if (active == null) {
        emit(ServerProfileError(
          profiles: state.profiles,
          activeProfile: state.activeProfile,
          message: 'No active server profile to update',
        ));
        return;
      }

      final updated = active.copyWith(
        gatewayUrl: gatewayUrl,
        token: token,
        model: model,
        temperature: temperature,
      );

      await _secureStorageService.saveServerProfile(updated);
      await _secureStorageService.saveSettings(
        baseUrl: updated.gatewayUrl,
        apiKey: updated.token,
        model: updated.model,
        temperature: updated.temperature,
      );

      final updatedProfiles = await _secureStorageService.getServerProfiles();
      final activeUpdated = updatedProfiles.firstWhere(
        (p) => p.isActive,
        orElse: () => updated,
      );

      emit(ServerProfileOperationSuccess(
        profiles: updatedProfiles,
        activeProfile: activeUpdated,
        message: 'Active profile "${activeUpdated.name}" updated',
      ));
    } catch (e) {
      emit(ServerProfileError(
        profiles: state.profiles,
        activeProfile: state.activeProfile,
        message: FailureMessage.humanize(
            e, context: 'Failed to update active profile'),
      ));
    }
  }

  /// Deletes the server profile with [id] from secure storage.
  ///
  /// If the active profile was deleted, switches to the first remaining profile if available.
  Future<void> deleteProfile(String id) async {
    emit(ServerProfileLoading(
      profiles: state.profiles,
      activeProfile: state.activeProfile,
    ));

    try {
      final wasActive = state.activeProfile?.id == id;
      await _secureStorageService.deleteServerProfile(id);

      final remaining = await _secureStorageService.getServerProfiles();
      if (wasActive && remaining.isNotEmpty) {
        await _secureStorageService.setActiveServerProfile(remaining.first.id, syncSettings: true);
      }

      final updatedProfiles = await _secureStorageService.getServerProfiles();
      ServerProfile? active;
      try {
        active = updatedProfiles.firstWhere((p) => p.isActive);
      } catch (_) {
        active = null;
      }

      emit(ServerProfileOperationSuccess(
        profiles: updatedProfiles,
        activeProfile: active,
        message: 'Server profile deleted',
      ));
    } catch (e) {
      emit(ServerProfileError(
        profiles: state.profiles,
        activeProfile: state.activeProfile,
        message: FailureMessage.humanize(
            e, context: 'Failed to delete server profile'),
      ));
    }
  }

  /// Updates the [lastConnected] timestamp on the profile with [id].
  Future<void> updateLastConnected(String id, DateTime timestamp) async {
    try {
      final profiles = await _secureStorageService.getServerProfiles();
      final index = profiles.indexWhere((p) => p.id == id);
      if (index != -1) {
        final updated = profiles[index].copyWith(lastConnected: timestamp);
        await _secureStorageService.saveServerProfile(updated);

        final refreshed = await _secureStorageService.getServerProfiles();
        ServerProfile? active;
        try {
          active = refreshed.firstWhere((p) => p.isActive);
        } catch (_) {
          active = null;
        }

        emit(ServerProfileLoaded(
          profiles: refreshed,
          activeProfile: active,
        ));
      }
    } catch (_) {
      // Background metric update failures shouldn't block UI state
    }
  }
}
