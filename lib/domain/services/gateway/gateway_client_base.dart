import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';

/// Abstract transport contract for the Hermes Universal Gateway client.
///
/// Lives in domain so [GatewayDeviceRpcReceiver] can depend on the
/// abstraction without importing the data-layer [GatewayClient] implementation.
abstract class GatewayClientBase {
  /// Current connection state.
  GatewayConnectionState get state;

  /// Stream of connection state transitions.
  Stream<GatewayConnectionState> get stateStream;

  /// Stream of all incoming [GatewayMessage] events.
  Stream<GatewayMessage> get messageStream;

  /// Stream of incoming text deltas from streaming generation.
  Stream<GatewayTextDeltaMessage> get textDeltaStream;

  /// Stream of incoming tool call requests sent from the server.
  Stream<GatewayToolCallRequestMessage> get toolCallRequestStream;

  /// Stream of incoming HITL elicitation requests sent from the server.
  Stream<GatewayElicitationRequestMessage> get elicitationRequestStream;

  /// Connects to the Hermes Gateway at [gatewayUrl] using [token].
  Future<void> connect(String gatewayUrl, {String? token});

  /// Connects using an active [ServerProfile].
  Future<void> connectWithProfile(ServerProfile profile);

  /// Sends a structured [GatewayMessage].
  void send(GatewayMessage message);

  /// Sends a raw JSON map across the WebSocket.
  void sendJson(Map<String, dynamic> json);

  /// Sends a tool execution result frame back to Hermes Gateway.
  void sendToolCallResponse({
    required String callId,
    Map<String, dynamic>? result,
    String? error,
  });

  /// Sends a HITL elicitation decision frame back to Hermes Gateway.
  void sendElicitationResponse({
    required String requestId,
    required bool approved,
    bool biometricVerified = false,
  });

  /// Sends a chat message frame across the gateway connection.
  void sendChatMessage(
    String content, {
    String role = 'user',
    Map<String, dynamic>? metadata,
  });

  /// Disconnects the socket and disables auto-reconnection.
  Future<void> disconnect({String? reason});

  /// Disposes resources, closes streams, and disconnects.
  Future<void> dispose();
}
