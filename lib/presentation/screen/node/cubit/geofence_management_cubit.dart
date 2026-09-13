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
  Future<String?> addGeofence({
    required String label,
    required double latitude,
    required double longitude,
    required double radiusMeters,
  }) async {
    final id = _generateId();
    final region = GeofenceRegion(
      id: id,
      name: label,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
    );
    final regions = [...state.regions, region];
    final ok = await _persist(regions);
    if (!ok) return null;
    _ambient.addGeofence(region);
    emit(state.copyWith(regions: regions, clearError: true));
    return id;
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
