import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_request.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';

part 'gateway_rpc_state.dart';

/// Cubit managing bidirectional hardware tool RPC dispatch from remote Hermes gateway.
///
/// This cubit is the single consumer of [GatewayClientBase.toolCallRequestStream].
/// It routes every request through [GatewayRpcReceiverBase.handleRequest] itself and
/// must never call `startListening()` on the injected receiver: a second subscription
/// on the same broadcast stream would execute each tool call twice and send two
/// responses. The receiver handed to this cubit is therefore left unsubscribed.
@injectable
class GatewayRpcCubit extends Cubit<GatewayRpcState> {
  final GatewayClientBase _gatewayClient;
  final ToolRegistry _toolRegistry;
  final GatewayRpcReceiverBase _rpcReceiver;
  final bool _ownsReceiver;

  final Map<String, Completer<bool>> _pendingApprovals = {};
  ToolCallRequest? _pendingApproval;
  StreamSubscription<GatewayToolCallRequestMessage>? _requestSubscription;
  StreamSubscription<GatewayElicitationRequestMessage>?
      _elicitationSubscription;

  final Map<String, Completer<ElicitationDecision>> _pendingElicitations = {};
  final Map<String, Timer> _elicitationTimers = {};
  final Duration _elicitationTimeout;

  @factoryMethod
  factory GatewayRpcCubit.create({
    required GatewayClientBase gatewayClient,
    required ToolRegistry toolRegistry,
  }) =>
      GatewayRpcCubit(
        gatewayClient: gatewayClient,
        toolRegistry: toolRegistry,
      );

  GatewayRpcCubit({
    required GatewayClientBase gatewayClient,
    required ToolRegistry toolRegistry,
    GatewayRpcReceiverBase? rpcReceiver,
    bool autoStart = true,
    Duration elicitationTimeout = const Duration(seconds: 120),
  })  : _gatewayClient = gatewayClient,
        _toolRegistry = toolRegistry,
        _elicitationTimeout = elicitationTimeout,
        _ownsReceiver = rpcReceiver == null,
        _rpcReceiver = rpcReceiver ??
            GatewayDeviceRpcReceiver(
              gatewayClient: gatewayClient,
              toolRegistry: toolRegistry,
            ),
        super(const GatewayRpcInitial()) {
    if (autoStart) {
      startListening();
    }
  }

  /// Registry of executable tools.
  ToolRegistry get toolRegistry => _toolRegistry;

  /// Current pending HITL approval request, if any.
  ToolCallRequest? get pendingApproval => _pendingApproval;

  /// Whether the RPC receiver is actively listening for incoming tool call requests.
  bool get isListening => _requestSubscription != null;

  /// Starts listening for incoming tool calls from Gateway.
  void startListening() {
    if (_requestSubscription != null) return;

    _requestSubscription = _gatewayClient.toolCallRequestStream.listen(
      _handleIncomingRequest,
      onError: (err) {
        emit(GatewayRpcError(FailureMessage.humanize(
            err, context: 'Gateway tool request stream error')));
      },
    );
    _elicitationSubscription = _gatewayClient.elicitationRequestStream.listen(
      _handleIncomingElicitation,
      onError: (err) {
        emit(GatewayRpcError(FailureMessage.humanize(
            err, context: 'Gateway elicitation stream error')));
      },
    );
  }

  /// Stops listening for incoming tool calls and elicitation requests.
  void stopListening() {
    _requestSubscription?.cancel();
    _requestSubscription = null;
    _elicitationSubscription?.cancel();
    _elicitationSubscription = null;
  }

  /// Aligns the RPC listener with the gateway connection lifecycle: listening
  /// whenever the link is live (connected/connecting/reconnecting) and stopped
  /// only when it is fully disconnected.
  ///
  /// On disconnect every pending elicitation is rejected locally and a rejection
  /// frame is *attempted*. The socket is already gone by then, so delivery is
  /// best effort only: the server still relies on its own timeout if the frame
  /// never lands.
  void syncWithConnectionState(GatewayConnectionState state) {
    if (state.isDisconnected) {
      stopListening();
      _rejectAllElicitations(notifyServer: true);
    } else {
      startListening();
    }
  }

  /// Handles incoming tool call request frame from gateway.
  Future<void> _handleIncomingRequest(
      GatewayToolCallRequestMessage request) async {
    emit(GatewayRpcExecuting(
      callId: request.id,
      tool: request.tool,
      arguments: request.arguments,
    ));

    try {
      final response = await _rpcReceiver.handleRequest(
        request,
        onApprovalRequired: (req) => _requestHitlApproval(req),
      );

      if (isClosed) return;
      emit(GatewayRpcCompleted(
        callId: response.id,
        tool: request.tool,
        result: response.result,
        error: response.error,
      ));
    } catch (e) {
      if (isClosed) return;
      emit(GatewayRpcError(
        FailureMessage.humanize(
            e, context: 'Failed to process tool call ${request.tool}'),
        callId: request.id,
      ));
    }
  }

  /// Requests user HITL approval for Tier 3 tool and returns a `Future<bool>`.
  Future<bool> _requestHitlApproval(ToolCallRequest request) {
    final completer = Completer<bool>();
    _pendingApprovals[request.id] = completer;
    _pendingApproval = request;

    emit(GatewayRpcWaitingApproval(request));
    return completer.future;
  }

  /// User approves the pending Tier 3 tool action.
  Future<void> approveAction(String callId) async {
    final completer = _pendingApprovals.remove(callId);
    if (completer != null && !completer.isCompleted) {
      if (_pendingApproval?.id == callId) {
        _pendingApproval = null;
      }
      completer.complete(true);
    }
  }

  /// User rejects the pending Tier 3 tool action.
  Future<void> rejectAction(String callId) async {
    final completer = _pendingApprovals.remove(callId);
    if (completer != null && !completer.isCompleted) {
      if (_pendingApproval?.id == callId) {
        _pendingApproval = null;
      }
      completer.complete(false);
    }
  }

  /// Handles incoming remote HITL elicitation request frame from gateway.
  void _handleIncomingElicitation(GatewayElicitationRequestMessage request) {
    if (isClosed) return;
    final requestId = request.requestId.trim();
    // No id means no way to address the response frame back: drop the request.
    if (requestId.isEmpty) return;

    if (_pendingElicitations.containsKey(requestId)) {
      // Server reused a live id. Resolve the old request first so its
      // Completer and Timer are never silently overwritten.
      _resolveElicitation(requestId, outcome: ElicitationOutcome.rejected);
    }

    _pendingElicitations[requestId] = Completer<ElicitationDecision>();
    _elicitationTimers[requestId] =
        Timer(_elicitationTimeout, () => rejectElicitation(requestId));

    emit(GatewayRpcElicitationPending(
      requestId: requestId,
      title: request.title,
      description: request.description,
      riskLevel: request.riskLevel,
      fields: request.fields,
      expiresAfter: _elicitationTimeout,
    ));
  }

  /// User approves the pending elicitation, dispatching the decision frame.
  Future<void> approveElicitation(String requestId,
      {bool biometricVerified = false}) {
    return _resolveElicitation(
      requestId,
      outcome: ElicitationOutcome.approved,
      biometricVerified: biometricVerified,
    );
  }

  /// User rejects (or the UI dismisses) the pending elicitation.
  Future<void> rejectElicitation(String requestId) {
    return _resolveElicitation(requestId, outcome: ElicitationOutcome.rejected);
  }

  Future<void> _resolveElicitation(
    String requestId, {
    required ElicitationOutcome outcome,
    bool biometricVerified = false,
    bool notifyServer = true,
  }) async {
    final completer = _pendingElicitations.remove(requestId);
    if (completer == null || completer.isCompleted) return;
    _elicitationTimers.remove(requestId)?.cancel();

    if (notifyServer) {
      try {
        _gatewayClient.sendElicitationResponse(
          requestId: requestId,
          approved: outcome == ElicitationOutcome.approved,
          biometricVerified: biometricVerified,
        );
      } catch (_) {
        // Dead socket must never break the local decision flow.
      }
    }

    if (!isClosed) {
      emit(GatewayRpcElicitationResolved(
        requestId: requestId,
        approved: outcome == ElicitationOutcome.approved,
      ));
    }
    completer.complete(ElicitationDecision(
      outcome: outcome,
      biometricVerified: biometricVerified,
    ));
  }

  void _rejectAllElicitations({required bool notifyServer}) {
    final requestIds = _pendingElicitations.keys.toList();
    if (!notifyServer) {
      // Close path: mirror tool-approval teardown, no frames and no emits.
      for (final timer in _elicitationTimers.values) {
        timer.cancel();
      }
      _elicitationTimers.clear();
      for (final requestId in requestIds) {
        final completer = _pendingElicitations.remove(requestId);
        if (completer != null && !completer.isCompleted) {
          completer.complete(
            const ElicitationDecision(outcome: ElicitationOutcome.rejected),
          );
        }
      }
      return;
    }
    for (final requestId in requestIds) {
      _resolveElicitation(
        requestId,
        outcome: ElicitationOutcome.rejected,
      );
    }
  }

  @override
  Future<void> close() async {
    stopListening();
    for (final completer in _pendingApprovals.values) {
      if (!completer.isCompleted) {
        completer.complete(false);
      }
    }
    _pendingApprovals.clear();
    _pendingApproval = null;
    _rejectAllElicitations(notifyServer: false);
    if (_ownsReceiver) {
      _rpcReceiver.dispose();
    }
    return super.close();
  }
}

/// Outcome of a remote HITL elicitation decision.
enum ElicitationOutcome { approved, rejected }

/// Immutable user decision for a server-initiated elicitation request.
class ElicitationDecision {
  final ElicitationOutcome outcome;
  final bool biometricVerified;

  const ElicitationDecision({
    required this.outcome,
    this.biometricVerified = false,
  });
}
