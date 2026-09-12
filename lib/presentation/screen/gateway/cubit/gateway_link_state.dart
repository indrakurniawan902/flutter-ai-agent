part of 'gateway_link_cubit.dart';

/// Immutable snapshot of the gateway link keepalive policy.
///
/// A single concrete state (mirrors `GatewayRpcState`'s file style rather than
/// a sealed hierarchy) describing whether the foreground service and wake lock
/// are currently held, how many times the link has flapped, and the last
/// connection state observed on [GatewayClientBase.stateStream].
class GatewayLinkState extends Equatable {
  /// Whether the background foreground-service is currently running.
  final bool serviceRunning;

  /// Whether a wake lock is currently held.
  final bool wakeLockHeld;

  /// Count of `connected -> disconnected` flaps observed so far.
  final int linkFlaps;

  /// Last gateway connection state applied to the policy.
  final GatewayConnectionState? lastConnectionState;

  const GatewayLinkState({
    this.serviceRunning = false,
    this.wakeLockHeld = false,
    this.linkFlaps = 0,
    this.lastConnectionState,
  });

  GatewayLinkState copyWith({
    bool? serviceRunning,
    bool? wakeLockHeld,
    int? linkFlaps,
    GatewayConnectionState? lastConnectionState,
  }) {
    return GatewayLinkState(
      serviceRunning: serviceRunning ?? this.serviceRunning,
      wakeLockHeld: wakeLockHeld ?? this.wakeLockHeld,
      linkFlaps: linkFlaps ?? this.linkFlaps,
      lastConnectionState: lastConnectionState ?? this.lastConnectionState,
    );
  }

  @override
  List<Object?> get props => [
        serviceRunning,
        wakeLockHeld,
        linkFlaps,
        lastConnectionState,
      ];
}
