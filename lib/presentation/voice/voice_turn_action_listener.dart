import 'dart:async';

import 'package:flutter/widgets.dart';

import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_turn_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/voice/chat_voice_prompt_dispatcher.dart';

/// Routes background-service actions to the shared voice/agent seam.
///
/// Lives above the router (wrapped around the whole app in `myapp.dart`) so the
/// "Voice Input" notification action runs one voice turn without ChatScreen
/// ever being mounted. It also registers the headless prompt transport; a
/// mounted ChatScreen later registers its own transport, which wins because the
/// registry prefers the newest READY entry.
class VoiceTurnActionListener extends StatefulWidget {
  const VoiceTurnActionListener({
    super.key,
    required this.child,
    this.backgroundService,
    this.voiceTurnService,
    this.registry,
    this.agentCubit,
  });

  final Widget child;
  final BackgroundServiceBase? backgroundService;
  final VoiceTurnServiceBase? voiceTurnService;
  final VoicePromptDispatcherRegistry? registry;
  final AgentCubit? agentCubit;

  @override
  State<VoiceTurnActionListener> createState() =>
      _VoiceTurnActionListenerState();
}

class _VoiceTurnActionListenerState extends State<VoiceTurnActionListener> {
  BackgroundServiceBase? _backgroundService;
  VoiceTurnServiceBase? _voiceTurnService;
  VoicePromptDispatcherRegistry? _registry;
  StreamSubscription<String>? _actionSub;
  AgentCubit? _cachedHeadlessCubit;

  @override
  void initState() {
    super.initState();
    _backgroundService = _resolveBackgroundService();
    _voiceTurnService = _resolveVoiceTurnService();
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
    unawaited(_checkPendingAction());
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
        unawaited(_voiceTurnService?.runTurn());
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
    _registry?.unregister('headless');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
