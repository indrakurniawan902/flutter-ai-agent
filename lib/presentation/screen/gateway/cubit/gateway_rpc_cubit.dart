import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/models/chat/tool_call_request.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';

part 'gateway_rpc_state.dart';

/// Cubit managing bidirectional hardware tool RPC dispatch from remote Hermes gateway.
@injectable
class GatewayRpcCubit extends Cubit<GatewayRpcState> {
  final GatewayClientBase _gatewayClient;
  final ToolRegistry _toolRegistry;
  final GatewayRpcReceiverBase _rpcReceiver;
  final bool _ownsReceiver;

  final Map<String, Completer<bool>> _pendingApprovals = {};
  ToolCallRequest? _pendingApproval;
  StreamSubscription<GatewayToolCallRequestMessage>? _requestSubscription;

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
  })  : _gatewayClient = gatewayClient,
        _toolRegistry = toolRegistry,
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
        emit(GatewayRpcError('Gateway tool request stream error: $err'));
      },
    );
  }

  /// Stops listening for incoming tool calls.
  void stopListening() {
    _requestSubscription?.cancel();
    _requestSubscription = null;
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
        'Failed to process tool call ${request.tool}: $e',
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
    if (_ownsReceiver) {
      _rpcReceiver.dispose();
    }
    return super.close();
  }
}
