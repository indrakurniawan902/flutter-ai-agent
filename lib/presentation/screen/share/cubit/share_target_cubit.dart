import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/domain/models/share/shared_payload.dart';
import 'package:flutter_ai_agent/domain/services/share/share_target_service.dart';
import 'package:flutter_ai_agent/presentation/screen/share/cubit/share_target_state.dart';

/// Routes OS share-target payloads into chat prompts.
@injectable
class ShareTargetCubit extends Cubit<ShareTargetState> {
  final ShareTargetService _service;
  StreamSubscription<List<SharedPayload>>? _subscription;

  ShareTargetCubit({required ShareTargetService service})
      : _service = service,
        super(const ShareTargetInitial());

  /// Subscribes to live shares and drains cold-start payloads.
  Future<void> init() async {
    emit(const ShareTargetListening());
    try {
      await _subscription?.cancel();
      _subscription = _service.payloadStream.listen(
        _onPayloads,
        onError: (Object e) => emit(ShareTargetError(e.toString())),
      );
      await _service.startListening();
      final initial = await _service.getInitialPayloads();
      if (initial.isNotEmpty) {
        _onPayloads(initial);
      }
    } catch (e) {
      emit(ShareTargetError(e.toString()));
    }
  }

  void _onPayloads(List<SharedPayload> payloads) {
    if (payloads.isEmpty || isClosed) return;
    emit(ShareTargetReceived(
      payloads: List.unmodifiable(payloads),
      suggestedPrompt: _service.buildSuggestedPrompt(payloads),
    ));
  }

  /// Returns pending payloads and returns to listening state.
  List<SharedPayload> consume() {
    final current = state;
    if (current is ShareTargetReceived) {
      final payloads = current.payloads;
      if (!isClosed) emit(const ShareTargetListening());
      unawaited(_service.reset());
      return payloads;
    }
    return const [];
  }

  /// Discards pending payloads and returns to listening state.
  Future<void> clearPayloads() async {
    try {
      await _service.reset();
    } catch (_) {
      // Reset failures must not break UI state.
    }
    if (!isClosed) emit(const ShareTargetListening());
  }

  @override
  Future<void> close() async {
    await _subscription?.cancel();
    _subscription = null;
    return super.close();
  }
}
