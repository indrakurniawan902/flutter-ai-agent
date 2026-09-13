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

/// State emitted while a remote HITL elicitation request awaits user decision.
class GatewayRpcElicitationPending extends GatewayRpcState {
  final String requestId;
  final String title;
  final String description;
  final String riskLevel;
  final Duration expiresAfter;

  const GatewayRpcElicitationPending({
    required this.requestId,
    required this.title,
    required this.description,
    required this.riskLevel,
    this.expiresAfter = const Duration(seconds: 120),
  });

  @override
  List<Object?> get props =>
      [requestId, title, description, riskLevel, expiresAfter];
}

/// State emitted once an elicitation request has been resolved locally.
class GatewayRpcElicitationResolved extends GatewayRpcState {
  final String requestId;
  final bool approved;

  const GatewayRpcElicitationResolved({
    required this.requestId,
    required this.approved,
  });

  @override
  List<Object?> get props => [requestId, approved];
}

/// State emitted on unhandled receiver errors.
class GatewayRpcError extends GatewayRpcState {
  final String message;
  final String? callId;

  const GatewayRpcError(this.message, {this.callId});

  @override
  List<Object?> get props => [message, callId];
}
