part of 'gateway_rpc_cubit.dart';

/// Base state for [GatewayRpcCubit].
sealed class GatewayRpcState extends Equatable {
  const GatewayRpcState();

  @override
  List<Object?> get props => [];
}

/// Initial state of Gateway RPC receiver.
class GatewayRpcInitial extends GatewayRpcState {
  const GatewayRpcInitial();
}

/// Active execution state for an incoming tool call request.
class GatewayRpcExecuting extends GatewayRpcState {
  final String callId;
  final String tool;
  final Map<String, dynamic> arguments;

  const GatewayRpcExecuting({
    required this.callId,
    required this.tool,
    this.arguments = const {},
  });

  @override
  List<Object?> get props => [callId, tool, arguments];
}

/// Paused state waiting for Human-in-the-Loop (HITL) confirmation of a Tier 3 tool.
class GatewayRpcWaitingApproval extends GatewayRpcState {
  final ToolCallRequest request;

  const GatewayRpcWaitingApproval(this.request);

  @override
  List<Object?> get props => [request];
}

/// State emitted when tool execution completes and response is returned to server.
class GatewayRpcCompleted extends GatewayRpcState {
  final String callId;
  final String tool;
  final Map<String, dynamic>? result;
  final String? error;

  const GatewayRpcCompleted({
    required this.callId,
    required this.tool,
    this.result,
    this.error,
  });

  @override
  List<Object?> get props => [callId, tool, result, error];
}

/// State emitted on unhandled receiver errors.
class GatewayRpcError extends GatewayRpcState {
  final String message;
  final String? callId;

  const GatewayRpcError(this.message, {this.callId});

  @override
  List<Object?> get props => [message, callId];
}
