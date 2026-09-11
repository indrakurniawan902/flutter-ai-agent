import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/features/gateway/domain/entities/gateway_connection_state.dart';

void main() {
  group('GatewayConnectionState', () {
    test('has all four required connection states', () {
      expect(GatewayConnectionState.values, [
        GatewayConnectionState.disconnected,
        GatewayConnectionState.connecting,
        GatewayConnectionState.connected,
        GatewayConnectionState.reconnecting,
      ]);
    });

    test('helper getters return correct boolean values', () {
      expect(GatewayConnectionState.disconnected.isDisconnected, isTrue);
      expect(GatewayConnectionState.disconnected.isConnected, isFalse);
      expect(GatewayConnectionState.disconnected.isConnecting, isFalse);
      expect(GatewayConnectionState.disconnected.isReconnecting, isFalse);

      expect(GatewayConnectionState.connecting.isConnecting, isTrue);
      expect(GatewayConnectionState.connecting.isConnected, isFalse);
      expect(GatewayConnectionState.connecting.isDisconnected, isFalse);
      expect(GatewayConnectionState.connecting.isReconnecting, isFalse);

      expect(GatewayConnectionState.connected.isConnected, isTrue);
      expect(GatewayConnectionState.connected.isConnecting, isFalse);
      expect(GatewayConnectionState.connected.isDisconnected, isFalse);
      expect(GatewayConnectionState.connected.isReconnecting, isFalse);

      expect(GatewayConnectionState.reconnecting.isReconnecting, isTrue);
      expect(GatewayConnectionState.reconnecting.isConnected, isFalse);
      expect(GatewayConnectionState.reconnecting.isConnecting, isFalse);
      expect(GatewayConnectionState.reconnecting.isDisconnected, isFalse);
    });
  });
}
