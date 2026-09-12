/// Connection states for the Hermes Universal Gateway WebSocket client.
enum GatewayConnectionState {
  /// The client is not connected to the gateway.
  disconnected,

  /// The client is establishing a connection or performing authentication handshake.
  connecting,

  /// The client is connected and authenticated with the gateway.
  connected,

  /// The client lost connection and is attempting to reconnect.
  reconnecting;

  /// Returns true if the client is currently connected and authenticated.
  bool get isConnected => this == GatewayConnectionState.connected;

  /// Returns true if the client is currently establishing a connection.
  bool get isConnecting => this == GatewayConnectionState.connecting;

  /// Returns true if the client is disconnected.
  bool get isDisconnected => this == GatewayConnectionState.disconnected;

  /// Returns true if the client is attempting to reconnect.
  bool get isReconnecting => this == GatewayConnectionState.reconnecting;
}
