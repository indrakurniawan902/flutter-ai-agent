import 'dart:math';

import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/presentation/screen/node/cubit/geofence_management_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Manages geofence regions on top of [SecureStorageService] (persistence),
/// [AmbientTriggerServiceBase] (live engine state) and [LocationServiceBase]
/// (current-location capture).
///
/// Constructed at the widget level (cubits are not registered in the service
/// locator in this repo).
class GeofenceManagementCubit extends Cubit<GeofenceManagementState> {
  final SecureStorageService _storage;
  final AmbientTriggerServiceBase _ambient;
  final LocationServiceBase _location;

  GeofenceManagementCubit({
    required SecureStorageService storage,
    required AmbientTriggerServiceBase ambient,
    required LocationServiceBase location,
  })  : _storage = storage,
        _ambient = ambient,
        _location = location,
        super(const GeofenceManagementState());

  /// Loads geofence regions by merging persisted storage state with the live
  /// engine, without wiping runtime-registered regions.
  Future<void> load() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final persisted = await _storage.getGeofences();
      final live = _ambient.regions;
      final mergedById = <String, GeofenceRegion>{
        for (final region in persisted) region.id: region,
        for (final region in live) region.id: region,
      };
      final merged = mergedById.values.toList();
      for (final region in merged) {
        if (!live.contains(region)) {
          _ambient.addGeofence(region);
        }
      }
      final persistedOk = await _persist(merged);
      emit(state.copyWith(
        regions: merged,
        isLoading: false,
        clearError: persistedOk,
      ));
    } catch (e) {
      emit(state.copyWith(isLoading: false, error: '$e'));
    }
  }

  /// Adds a new [GeofenceRegion], persists it, and returns its id.
  ///
  /// Invalid input emits an error state and returns `null` without persisting
  /// or touching the live engine. The action/payload pair is held to the same
  /// binding rule as the register_geofence tool via
  /// [geofenceActionBindingError], so a region can never be stored bound to
  /// runPrompt/openUrl without a payload.
  ///
  /// [action], [actionPayload] and [actionOn] bind what crossing the region
  /// does; they default to no action.
  Future<String?> addGeofence({
    required String label,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    GeofenceAction action = GeofenceAction.none,
    String actionPayload = '',
    GeofenceActionTrigger actionOn = GeofenceActionTrigger.both,
  }) async {
    final validationError = _validateGeofence(
      label: label,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
    if (validationError != null) {
      emit(state.copyWith(error: validationError));
      return null;
    }
    final bindingError = _validateActionBinding(action, actionPayload);
    if (bindingError != null) {
      emit(state.copyWith(error: bindingError));
      return null;
    }
    final id = _generateId();
    final region = GeofenceRegion(
      id: id,
      name: label,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      action: action,
      actionPayload: actionPayload,
      actionOn: actionOn,
    );
    final regions = [...state.regions, region];
    final ok = await _persist(regions);
    if (!ok) return null;
    _ambient.addGeofence(region);
    emit(state.copyWith(regions: regions, clearError: true));
    return id;
  }

  /// Updates the region with [id] in place, preserving its id and enabled flag.
  ///
  /// Returns `false` without persisting or touching the live engine when the
  /// region does not exist, the input is invalid, or persistence fails. The
  /// resulting action/payload pair must satisfy [geofenceActionBindingError],
  /// so an update can never strip the payload a runPrompt/openUrl action needs.
  Future<bool> updateGeofence(
    String id, {
    required String label,
    required double latitude,
    required double longitude,
    required double radiusMeters,
    GeofenceAction? action,
    String? actionPayload,
    GeofenceActionTrigger? actionOn,
  }) async {
    final index = state.regions.indexWhere((r) => r.id == id);
    if (index < 0) {
      emit(state.copyWith(error: 'Geofence not found'));
      return false;
    }
    final validationError = _validateGeofence(
      label: label,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
    if (validationError != null) {
      emit(state.copyWith(error: validationError));
      return false;
    }
    final existing = state.regions[index];
    final bindingError = _validateActionBinding(
      action ?? existing.action,
      actionPayload ?? existing.actionPayload,
    );
    if (bindingError != null) {
      emit(state.copyWith(error: bindingError));
      return false;
    }
    final updatedRegion = existing.copyWith(
      name: label,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      action: action,
      actionPayload: actionPayload,
      actionOn: actionOn,
    );
    final regions = [...state.regions];
    regions[index] = updatedRegion;
    final ok = await _persist(regions);
    if (!ok) return false;
    _ambient.addGeofence(updatedRegion);
    emit(state.copyWith(regions: regions, clearError: true));
    return true;
  }

  /// Toggles the enabled flag of the region with [id].
  Future<void> toggleGeofence(String id) async {
    final regions = state.regions
        .map((r) => r.id == id ? r.copyWith(isEnabled: !r.isEnabled) : r)
        .toList();
    final updated = regions.firstWhere((r) => r.id == id);
    _ambient.toggleGeofence(id, updated.isEnabled);
    final ok = await _persist(regions);
    emit(state.copyWith(regions: regions, clearError: ok));
  }

  /// Removes the region with [id], persists, and clears it from the live engine.
  Future<void> removeGeofence(String id) async {
    _ambient.removeGeofence(id);
    final regions = state.regions.where((r) => r.id != id).toList();
    final ok = await _persist(regions);
    emit(state.copyWith(regions: regions, clearError: ok));
  }

  /// Captures the current device location and returns latitude/longitude.
  ///
  /// Returns `null` when the location cannot be obtained.
  Future<({double latitude, double longitude})?> captureCurrentLocation() async {
    final result = await _location.getLocation();
    return result.fold(
      (_) => null,
      (data) {
        final latRaw = data['latitude'];
        final lat = latRaw is num ? latRaw : data['lat'];
        final lngRaw = data['longitude'];
        final lng = lngRaw is num ? lngRaw : data['lng'];
        if (lat is! num || lng is! num) return null;
        return (latitude: lat.toDouble(), longitude: lng.toDouble());
      },
    );
  }

  /// Validates geofence input shared by add and update.
  ///
  /// Returns a human-readable message when invalid, otherwise `null`.
  String? _validateGeofence({
    required String label,
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) {
    if (label.trim().isEmpty) return 'Name is required';
    if (!latitude.isFinite || latitude < -90 || latitude > 90) {
      return 'Latitude must be between -90 and 90';
    }
    if (!longitude.isFinite || longitude < -180 || longitude > 180) {
      return 'Longitude must be between -180 and 180';
    }
    if (!radiusMeters.isFinite || radiusMeters <= 0 || radiusMeters > 10000) {
      return 'Radius must be greater than 0 and at most 10000 meters';
    }
    return null;
  }

  /// Enforces the shared action/payload binding rule from the domain entity,
  /// so this cubit and the register_geofence tool can never disagree.
  ///
  /// Returns the helper's message verbatim, or `null` when the pair is valid.
  String? _validateActionBinding(
    GeofenceAction action,
    String actionPayload,
  ) {
    return geofenceActionBindingError(
      rawAction: action.name,
      actionPayload: actionPayload,
    );
  }

  Future<bool> _persist(List<GeofenceRegion> regions) async {
    try {
      await _storage.saveGeofences(regions);
      return true;
    } catch (e) {
      emit(state.copyWith(error: '$e'));
      return false;
    }
  }

  String _generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(0xFFFFFF).toRadixString(16).padLeft(6, '0');
    return 'gf-$now-$rand';
  }
}
