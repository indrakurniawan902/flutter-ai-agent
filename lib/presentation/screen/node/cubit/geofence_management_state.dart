import 'package:equatable/equatable.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';

/// Immutable state for [GeofenceManagementCubit].
class GeofenceManagementState extends Equatable {
  /// Loaded geofence regions.
  final List<GeofenceRegion> regions;

  /// True while geofences are being loaded or persisted.
  final bool isLoading;

  /// Human-readable failure from the last operation, if any.
  final String? error;

  const GeofenceManagementState({
    this.regions = const [],
    this.isLoading = false,
    this.error,
  });

  GeofenceManagementState copyWith({
    List<GeofenceRegion>? regions,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return GeofenceManagementState(
      regions: regions ?? this.regions,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [regions, isLoading, error];
}
