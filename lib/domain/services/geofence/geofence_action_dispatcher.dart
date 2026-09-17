import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';

/// Executes the action bound to a geofence [GeofenceRegion] when it crosses.
///
/// Best-effort by contract: [dispatch] must never throw and must never change
/// the `AmbientCheckResult` an ambient check returns. A region with
/// [GeofenceAction.none] is a no-op, and a trigger mismatch
/// ([GeofenceRegion.matchesEvent] false) is ignored.
abstract class GeofenceActionDispatcherBase {
  /// Runs [region]'s bound action for [event].
  ///
  /// Implemented in `lib/data/services/geofence/`. Collaborators that are
  /// missing, or that fail, turn the call into a silent no-op.
  Future<void> dispatch(GeofenceRegion region, AmbientEvent event);
}
