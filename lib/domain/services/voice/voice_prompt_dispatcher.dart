import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';

/// Carries a voice transcript to the agent over whichever transport is live.
abstract class VoicePromptDispatcherBase {
  /// Stable id used by [VoicePromptDispatcherRegistry]; newest registered id wins.
  String get transportId;

  /// Whether this transport can accept a prompt right now.
  bool get isReady;

  /// Sends [prompt] and resolves with the assistant's final reply text.
  Future<Either<Failure, String>> dispatch(String prompt);

  /// Aborts an in-flight [dispatch]; safe to call when idle.
  Future<void> cancel();
}

/// Ordered registry of the transports a voice turn may use.
///
/// Surfaces register the transport they own (a mounted ChatScreen registers its
/// own cubit-backed transport; the app-level listener registers a headless
/// fallback). The most recently registered READY transport wins, so a live
/// ChatScreen keeps the UI in sync while it exists and the fallback takes over
/// once it is gone.
@lazySingleton
class VoicePromptDispatcherRegistry {
  final Map<String, VoicePromptDispatcherBase> _byId = {};
  final List<String> _order = [];

  void register(VoicePromptDispatcherBase dispatcher) {
    final String id = dispatcher.transportId;
    _byId[id] = dispatcher;
    _order.remove(id);
    _order.add(id);
  }

  void unregister(String transportId) {
    _byId.remove(transportId);
    _order.remove(transportId);
  }

  VoicePromptDispatcherBase? get active {
    for (var i = _order.length - 1; i >= 0; i--) {
      final VoicePromptDispatcherBase? candidate = _byId[_order[i]];
      if (candidate != null && candidate.isReady) {
        return candidate;
      }
    }
    return null;
  }

  bool get hasReadyTransport => active != null;

  void clear() {
    _byId.clear();
    _order.clear();
  }
}
