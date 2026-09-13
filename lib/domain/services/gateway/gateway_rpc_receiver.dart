import 'dart:async';
import 'dart:convert';

import 'package:flutter_ai_agent/domain/entities/chat/tool_call_request.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';

/// Callback invoked when a Tier 3 tool requires Human-in-the-Loop (HITL) approval.
/// Returns `true` if approved by user, `false` if rejected.
typedef HitlApprovalCallback = Future<bool> Function(ToolCallRequest request);

/// Interface for Gateway device RPC receiver.
abstract class GatewayRpcReceiverBase {
  bool get isListening;
  void startListening();
  void stopListening();
  Future<GatewayToolCallResponseMessage> handleRequest(
    GatewayToolCallRequestMessage request, {
    HitlApprovalCallback? onApprovalRequired,
  });
  void dispose();
}

/// Listens for `tool_call_request` messages over [GatewayClientBase],
/// evaluates tool security tiers with [SecurityPolicy], enforces HITL approval for Tier 3,
/// executes tools via [ToolRegistry], and sends `tool_call_response` frames back to Hermes server.
class GatewayDeviceRpcReceiver implements GatewayRpcReceiverBase {
  final GatewayClientBase gatewayClient;
  final ToolRegistry toolRegistry;
  final HitlApprovalCallback? onApprovalRequired;

  StreamSubscription<GatewayToolCallRequestMessage>? _subscription;
  bool _disposed = false;

  GatewayDeviceRpcReceiver({
    required this.gatewayClient,
    required this.toolRegistry,
    this.onApprovalRequired,
  });

  @override
  bool get isListening => _subscription != null;

  @override
  void startListening() {
    if (_disposed || _subscription != null) return;

    _subscription = gatewayClient.toolCallRequestStream.listen(
      (request) {
        handleRequest(request, onApprovalRequired: onApprovalRequired);
      },
      onError: (_) {
        // Ignore stream errors
      },
    );
  }

  @override
  void stopListening() {
    _subscription?.cancel();
    _subscription = null;
  }

  @override
  Future<GatewayToolCallResponseMessage> handleRequest(
    GatewayToolCallRequestMessage request, {
    HitlApprovalCallback? onApprovalRequired,
  }) async {
    final tool = toolRegistry.getTool(request.tool);

    if (tool == null) {
      final response = GatewayToolCallResponseMessage(
        id: request.id,
        result: null,
        error: 'Tool not found: ${request.tool}',
      );
      gatewayClient.sendToolCallResponse(
        callId: request.id,
        result: null,
        error: response.error,
      );
      return response;
    }

    // Check Tier 3 HITL approval
    if (SecurityPolicy.requiresHitl(tool.securityTier)) {
      final callback = onApprovalRequired ?? this.onApprovalRequired;
      if (callback == null) {
        final response = GatewayToolCallResponseMessage(
          id: request.id,
          result: null,
          error:
              'Action ${request.tool} requires user approval, but no approval handler was registered.',
        );
        gatewayClient.sendToolCallResponse(
          callId: request.id,
          result: null,
          error: response.error,
        );
        return response;
      }

      final approvalRequest = ToolCallRequest(
        id: request.id,
        name: request.tool,
        parameters: request.arguments,
      );

      bool approved;
      try {
        approved = await callback(approvalRequest);
      } catch (e) {
        final response = GatewayToolCallResponseMessage(
          id: request.id,
          result: null,
          error: 'Approval request failed: $e',
        );
        gatewayClient.sendToolCallResponse(
          callId: request.id,
          result: null,
          error: response.error,
        );
        return response;
      }

      if (!approved) {
        final response = GatewayToolCallResponseMessage(
          id: request.id,
          result: null,
          error: 'Action ${request.tool} was rejected by user.',
        );
        gatewayClient.sendToolCallResponse(
          callId: request.id,
          result: null,
          error: response.error,
        );
        return response;
      }
    }

    // Execute tool
    GatewayToolCallResponseMessage response;
    try {
      final resultEither = await toolRegistry.executeTool(
        request.tool,
        request.arguments,
      );

      response = resultEither.fold(
        (failure) {
          final res = GatewayToolCallResponseMessage(
            id: request.id,
            result: null,
            error: failure.message,
          );
          gatewayClient.sendToolCallResponse(
            callId: request.id,
            result: null,
            error: res.error,
          );
          return res;
        },
        (rawResult) {
          final resultMap = _parseToolResult(rawResult);
          final res = GatewayToolCallResponseMessage(
            id: request.id,
            result: resultMap,
            error: null,
          );
          gatewayClient.sendToolCallResponse(
            callId: request.id,
            result: resultMap,
            error: null,
          );
          return res;
        },
      );
    } catch (e) {
      response = GatewayToolCallResponseMessage(
        id: request.id,
        result: null,
        error: 'Tool execution error: $e',
      );
      gatewayClient.sendToolCallResponse(
        callId: request.id,
        result: null,
        error: response.error,
      );
    }

    return response;
  }

  /// Parses raw tool result string to a `Map<String, dynamic>` payload for Gateway.
  static Map<String, dynamic> _parseToolResult(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      } else if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      } else if (decoded is List) {
        return {'data': decoded, 'items': decoded};
      } else {
        return {'result': decoded, 'output': decoded};
      }
    } catch (_) {
      return {'result': raw, 'output': raw};
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    stopListening();
  }
}
