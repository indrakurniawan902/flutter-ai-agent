import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_turn_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/overlay_bubble_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/voice/chat_voice_prompt_dispatcher.dart';

/// Routes background-service actions to the shared voice/agent seam.
///
/// Lives above the router (wrapped around the whole app in `myapp.dart`) so the
/// "Voice Input" notification action runs one voice turn without ChatScreen
/// ever being mounted. It also registers the headless prompt transport; a
/// mounted ChatScreen later registers its own transport, which wins because the
/// registry prefers the newest READY entry. While a turn runs, the overlay
/// bubble's recording indicator mirrors the turn phase stream.
class VoiceTurnActionListener extends StatefulWidget {
  const VoiceTurnActionListener({
    super.key,
    required this.child,
    this.backgroundService,
    this.voiceTurnService,
    this.overlayBubbleService,
    this.registry,
    this.agentCubit,
  });

  final Widget child;
  final BackgroundServiceBase? backgroundService;
  final VoiceTurnServiceBase? voiceTurnService;

  /// Overlay bubble seam; resolved from DI when omitted.
  final OverlayBubbleServiceBase? overlayBubbleService;

  final VoicePromptDispatcherRegistry? registry;
  final AgentCubit? agentCubit;

  @override
  State<VoiceTurnActionListener> createState() =>
      _VoiceTurnActionListenerState();
}

class _VoiceTurnActionListenerState extends State<VoiceTurnActionListener> {
  BackgroundServiceBase? _backgroundService;
  VoiceTurnServiceBase? _voiceTurnService;
  OverlayBubbleServiceBase? _overlayBubbleService;
  VoicePromptDispatcherRegistry? _registry;
  StreamSubscription<String>? _actionSub;
  StreamSubscription<VoiceTurnPhase>? _phaseSub;
  AgentCubit? _cachedHeadlessCubit;
  bool _turnInFlight = false;

  @override
  void initState() {
    super.initState();
    _backgroundService = _resolveBackgroundService();
    _voiceTurnService = _resolveVoiceTurnService();
    _overlayBubbleService = _resolveOverlayBubbleService();
    _registry = _resolveRegistry();
    // Headless fallback stays registered while no screen exists; a mounted
    // ChatScreen registers 'chat' later and wins as the newest READY entry.
    _registry?.register(
      ChatVoicePromptDispatcher(
        resolveCubit: _headlessCubit,
        resolveGatewayClient: _resolveGatewayClient,
        transportId: 'headless',
      ),
    );
    // Subscribe synchronously so one pump() in widget tests observes actions.
    _actionSub = _backgroundService?.actionStream.listen(_handleAction);
    _phaseSub = _voiceTurnService?.phaseStream.listen(_handlePhase);
    unawaited(_checkPendingAction());
    unawaited(_restoreBubble());
  }

  BackgroundServiceBase? _resolveBackgroundService() {
    if (widget.backgroundService != null) {
      return widget.backgroundService;
    }
    try {
      return sl.isRegistered<BackgroundServiceBase>()
          ? sl<BackgroundServiceBase>()
          : null;
    } catch (_) {
      return null;
    }
  }

  VoiceTurnServiceBase? _resolveVoiceTurnService() {
    if (widget.voiceTurnService != null) {
      return widget.voiceTurnService;
    }
    try {
      return sl.isRegistered<VoiceTurnServiceBase>()
          ? sl<VoiceTurnServiceBase>()
          : null;
    } catch (_) {
      return null;
    }
  }

  OverlayBubbleServiceBase? _resolveOverlayBubbleService() {
    if (widget.overlayBubbleService != null) {
      return widget.overlayBubbleService;
    }
    try {
      return sl.isRegistered<OverlayBubbleServiceBase>()
          ? sl<OverlayBubbleServiceBase>()
          : null;
    } catch (_) {
      return null;
    }
  }

  VoicePromptDispatcherRegistry? _resolveRegistry() {
    if (widget.registry != null) {
      return widget.registry;
    }
    try {
      return sl.isRegistered<VoicePromptDispatcherRegistry>()
          ? sl<VoicePromptDispatcherRegistry>()
          : null;
    } catch (_) {
      return null;
    }
  }

  GatewayClientBase? _resolveGatewayClient() {
    try {
      return sl.isRegistered<GatewayClientBase>()
          ? sl<GatewayClientBase>()
          : null;
    } catch (_) {
      return null;
    }
  }

  // Cache the first resolved cubit so every headless turn reuses one instance.
  AgentCubit? _headlessCubit() {
    if (widget.agentCubit != null) {
      return widget.agentCubit;
    }
    if (_cachedHeadlessCubit != null) {
      return _cachedHeadlessCubit;
    }
    try {
      if (!sl.isRegistered<AgentCubit>()) {
        return null;
      }
      _cachedHeadlessCubit = sl<AgentCubit>();
      return _cachedHeadlessCubit;
    } catch (_) {
      return null;
    }
  }

  void _handleAction(String action) {
    switch (action.toLowerCase().trim()) {
      case 'voice_input':
        unawaited(_runTurnWithTileSync());
        break;
      case 'cancel_voice':
        unawaited(_cancelTurnAndResetTile());
        break;
      case 'quick_status':
        unawaited(
          _registry?.active?.dispatch(
            'Quick status check: summarize battery, device context, and agent readiness.',
          ),
        );
        break;
    }
  }

  // The bubble indicator follows the turn phase stream; the native tap only
  // optimistically flips it, this stream is the authoritative correction.
  // The ongoing notification is the only user-visible surface of a headless
  // turn, so a finished or failed turn must stop the "Voice turn running" claim.
  void _handlePhase(VoiceTurnPhase phase) {
    final recording = phase == VoiceTurnPhase.listening ||
        phase == VoiceTurnPhase.dispatching;
    unawaited(_setBubbleRecording(recording));
    if (phase == VoiceTurnPhase.done) {
      unawaited(
        _updateNotification(
          title: 'Flames Agent Active',
          content: 'Voice turn finished',
        ),
      );
    } else if (phase == VoiceTurnPhase.error) {
      unawaited(
        _updateNotification(
          title: 'Flames Agent Active',
          content: 'Voice turn failed - open Flames for details',
        ),
      );
    }
  }

  Future<void> _updateNotification({
    required String title,
    required String content,
  }) async {
    try {
      await _backgroundService?.updateNotification(
        title: title,
        content: content,
      );
    } catch (_) {
      // A broken notification seam must never break a voice turn.
    }
  }

  Future<void> _setBubbleRecording(bool recording) async {
    try {
      await _overlayBubbleService?.setRecording(recording);
    } catch (_) {
      // A broken overlay seam must never break a voice turn.
    }
  }

  // The user enabled the bubble from Settings, so a process restart must bring
  // it back; a false preference (or missing seam) keeps the feature OFF.
  Future<void> _restoreBubble() async {
    try {
      final overlay = _overlayBubbleService;
      if (overlay == null) {
        return;
      }
      if (await overlay.isBubbleEnabled()) {
        await overlay.setBubbleEnabled(true);
      }
    } catch (_) {
      // A broken overlay seam must never block startup.
    }
  }

  /// Runs exactly one headless turn and mirrors it on the Quick Settings tile:
  /// active while recording, inactive once the turn settles. Fire-and-forget
  /// for the stream handler; awaited here so the tile reset is real.
  Future<void> _runTurnWithTileSync() async {
    final turnService = _voiceTurnService;
    if (turnService == null) {
      return;
    }
    if (_turnInFlight) {
      // The in-flight turn owns the tile; let the single-flight service
      // reject this one without touching the tile state.
      await turnService.runTurn();
      return;
    }
    _turnInFlight = true;
    await _setTileState(QuickTileState.active);
    try {
      await turnService.runTurn();
    } finally {
      _turnInFlight = false;
      await _setTileState(QuickTileState.inactive);
    }
  }

  /// Tile removed mid-turn: stop the recorder and never leave the tile active.
  Future<void> _cancelTurnAndResetTile() async {
    try {
      await _voiceTurnService?.cancelTurn();
    } catch (_) {}
    await _setTileState(QuickTileState.inactive);
  }

  /// Best-effort tile push. A missing service or a throwing channel must never
  /// break the turn; the returned Either is deliberately ignored.
  Future<void> _setTileState(QuickTileState state) async {
    try {
      await _backgroundService?.setTileState(state);
    } catch (_) {}
  }

  Future<void> _checkPendingAction() async {
    final pending = await _backgroundService?.getPendingAction();
    if (pending != null) {
      _handleAction(pending);
      await _backgroundService?.clearPendingAction();
    }
  }

  @override
  void dispose() {
    unawaited(_actionSub?.cancel());
    unawaited(_phaseSub?.cancel());
    _registry?.unregister('headless');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
