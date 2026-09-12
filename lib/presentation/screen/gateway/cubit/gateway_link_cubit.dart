import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';

part 'gateway_link_state.dart';

/// Cubit that owns the "keep the device reachable" policy on top of
/// [GatewayClientBase] + [BackgroundServiceBase].
///
/// It binds the foreground-service + wake-lock lifetime to the gateway
/// connection state, and forces an immediate re-fire on app resume instead
/// of waiting for the transport's backoff. The cubit never touches the
/// socket directly; it only reacts to state changes and requests reconnects.
@injectable
class GatewayLinkCubit extends Cubit<GatewayLinkState> with WidgetsBindingObserver {
  final GatewayClientBase _gatewayClient;
  final BackgroundServiceBase _backgroundService;

  /// Maximum consecutive flaps before the give-up flag is set.
  /// Default `0` means the policy never permanently gives up while the
  /// process is alive; resumed lifecycle events still fire retries.
  final int maxLinkRetries;

  static const String _tag = 'gw_link';
  static const Duration _wakeLockTimeout = Duration(minutes: 10);
  static const String _serviceTitle = 'Flames gateway link';
  static const String _serviceContent = 'Keeping the device reachable for Hermes';

  ServerProfile? _profile;
  StreamSubscription<GatewayConnectionState>? _stateSub;
  bool _subscribed = false;
  bool _gaveUp = false;
  int _linkFlaps = 0;
  GatewayConnectionState? _lastConnState;
  Future<void> _pending = Future<void>.value();

  @factoryMethod
  factory GatewayLinkCubit.create({
    required GatewayClientBase gatewayClient,
    required BackgroundServiceBase backgroundService,
  }) =>
      GatewayLinkCubit(gatewayClient: gatewayClient, backgroundService: backgroundService);

  GatewayLinkCubit({
    required GatewayClientBase gatewayClient,
    required BackgroundServiceBase backgroundService,
    bool autoStart = true,
    this.maxLinkRetries = 0,
  })  : _gatewayClient = gatewayClient,
        _backgroundService = backgroundService,
        super(const GatewayLinkState()) {
    if (autoStart) {
      _ensureSubscribed();
      ensureServiceForCurrentState();
    }
  }

  void _ensureSubscribed() {
    if (_subscribed) return;
    _subscribed = true;
    WidgetsBinding.instance.addObserver(this);
    _stateSub = _gatewayClient.stateStream.listen(
      _onStateEvent,
      onError: (Object err) => _log('state stream error: $err'),
    );
  }

  void _onStateEvent(GatewayConnectionState state) {
    _pending = _pending.then((_) => _apply(state)).catchError((Object e) {
      _log('apply failed: $e');
    });
  }

  /// Applies the keepalive policy for the gateway's current connection state.
  Future<void> ensureServiceForCurrentState() => _apply(_gatewayClient.state);

  Future<void> _apply(GatewayConnectionState state) async {
    final bool live = state == GatewayConnectionState.connected ||
        state == GatewayConnectionState.connecting ||
        state == GatewayConnectionState.reconnecting;

    if (live) {
      if (!await _backgroundService.isRunning()) {
        await _backgroundService.startService(
          title: _serviceTitle,
          content: _serviceContent,
        );
        _log('startService (${state.name})');
      }
      if (state == GatewayConnectionState.connected &&
          !await _backgroundService.isWakeLockHeld()) {
        await _backgroundService.acquireWakeLock(timeout: _wakeLockTimeout);
        _log('acquireWakeLock timeout=${_wakeLockTimeout.inMinutes}m');
      }
    }

    if (state == GatewayConnectionState.disconnected) {
      final bool wasConnected = _lastConnState == GatewayConnectionState.connected;
      if (await _backgroundService.isWakeLockHeld()) {
        await _backgroundService.releaseWakeLock();
        _log('releaseWakeLock');
      }
      if (await _backgroundService.isRunning()) {
        await _backgroundService.stopService();
        _log('stopService');
      }
      if (wasConnected) {
        _linkFlaps++;
        if (maxLinkRetries > 0 && _linkFlaps >= maxLinkRetries && !_gaveUp) {
          _gaveUp = true;
          _log('link give-up cap reached flaps=$_linkFlaps (policy keeps retrying)');
        }
      }
    }

    _lastConnState = state;
    await _emitFromService(state);
  }

  Future<void> _emitFromService(GatewayConnectionState? state) async {
    if (isClosed) return;
    emit(GatewayLinkState(
      serviceRunning: await _backgroundService.isRunning(),
      wakeLockHeld: await _backgroundService.isWakeLockHeld(),
      linkFlaps: _linkFlaps,
      lastConnectionState: state,
    ));
  }

  /// Stores [profile], ensures the link policy is observing, and opens the
  /// socket through the client (the client owns the socket).
  Future<void> startWithProfile(ServerProfile profile) async {
    _profile = profile;
    _ensureSubscribed();
    _log('startWithProfile id=${profile.id}');
    await _gatewayClient.connectWithProfile(profile);
  }

  /// Immediate re-fire used by the resume lifecycle hook and callers.
  Future<void> retryNow() async {
    final p = _profile;
    if (p == null) {
      _log('retryNow skipped: no profile');
      return;
    }
    if (!_gatewayClient.state.isDisconnected) {
      _log('retryNow skipped: not disconnected');
      return;
    }
    _gaveUp = false;
    _log('retryNow connectWithProfile id=${p.id}');
    await _gatewayClient.connectWithProfile(p);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // paused/inactive: leave the socket intact.
      return;
    }
    final conn = _gatewayClient.state;
    if (conn.isDisconnected) {
      unawaited(retryNow());
    } else if (conn.isConnected) {
      unawaited(_refreshWakeLock());
    }
  }

  Future<void> _refreshWakeLock() async {
    await _backgroundService.acquireWakeLock(timeout: _wakeLockTimeout);
    _log('refreshWakeLock on resume');
    await _emitFromService(_gatewayClient.state);
  }

  @override
  Future<void> close() async {
    if (_subscribed) {
      WidgetsBinding.instance.removeObserver(this);
      _subscribed = false;
    }
    await _stateSub?.cancel();
    _stateSub = null;
    return super.close();
  }

  void _log(String msg) => debugPrint('$_tag: $msg');
}