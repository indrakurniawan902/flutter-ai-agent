import 'package:equatable/equatable.dart';

import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';

/// Outcome of one [GeofenceActionDispatcherBase.dispatch] call.
///
/// A record is produced even when nothing ran, so a caller (and the tool
/// output) can tell "the region had no action" from "the action failed".
class GeofenceDispatchResult extends Equatable {
  final GeofenceAction action;

  /// True only when the action actually ran to completion.
  final bool executed;

  /// The trimmed payload the action carried; `''` when the action takes none.
  final String payload;

  /// Set only for [GeofenceAction.runPrompt]: which transport took the prompt.
  final String? transportId;

  /// Short machine-readable reason or result, e.g. `notification`,
  /// `prompt_dispatched`, `no_ready_transport`.
  final String? detail;

  const GeofenceDispatchResult({
    required this.action,
    required this.executed,
    this.payload = '',
    this.transportId,
    this.detail,
  });

  GeofenceDispatchResult copyWith({
    GeofenceAction? action,
    bool? executed,
    String? payload,
    String? transportId,
    String? detail,
  }) {
    return GeofenceDispatchResult(
      action: action ?? this.action,
      executed: executed ?? this.executed,
      payload: payload ?? this.payload,
      transportId: transportId ?? this.transportId,
      detail: detail ?? this.detail,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'action': geofenceActionToJson(action),
      'executed': executed,
      'payload': payload,
      if (transportId != null) 'transportId': transportId,
      if (detail != null) 'detail': detail,
    };
  }

  factory GeofenceDispatchResult.fromJson(Map<String, dynamic> json) {
    final rawExecuted = json['executed'];
    final rawTransport = json['transportId'] ?? json['transport_id'];
    final rawDetail = json['detail'];
    return GeofenceDispatchResult(
      action: geofenceActionFromJson(json['action']),
      executed: rawExecuted is bool
          ? rawExecuted
          : '$rawExecuted'.trim().toLowerCase() == 'true',
      payload: json['payload']?.toString() ?? '',
      transportId: rawTransport?.toString(),
      detail: rawDetail?.toString(),
    );
  }

  @override
  List<Object?> get props => [action, executed, payload, transportId, detail];
}

/// Executes the action bound to a geofence [GeofenceRegion] when it crosses.
///
/// Best-effort by contract: [dispatch] must never throw and must never change
/// the events an ambient check returns. It now also REPORTS what it did via
/// [GeofenceDispatchResult]. A region with [GeofenceAction.none] is a no-op,
/// and a trigger mismatch ([GeofenceRegion.matchesEvent] false) is ignored.
abstract class GeofenceActionDispatcherBase {
  /// Runs [region]'s bound action for [event] and reports the outcome.
  ///
  /// Implemented in `lib/data/services/geofence/`. Collaborators that are
  /// missing, or that fail, produce `executed: false` with a reason instead of
  /// a throw.
  Future<GeofenceDispatchResult> dispatch(
    GeofenceRegion region,
    AmbientEvent event,
  );
}
