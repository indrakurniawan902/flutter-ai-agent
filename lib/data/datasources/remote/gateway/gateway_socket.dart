import 'dart:async';
import 'dart:io';

/// Abstraction for a WebSocket connection to the Hermes Gateway.
abstract class GatewaySocket {
  /// Incoming stream of frames (text or binary).
  Stream<dynamic> get stream;

  /// Sends a text frame across the socket.
  void send(String data);

  /// Closes the socket connection.
  Future<void> close([int? code, String? reason]);

  /// WebSocket close code reported by the peer; null until the socket closes.
  int? get closeCode;

  /// WebSocket close reason reported by the peer; null until the socket closes.
  String? get closeReason;
}

/// Factory for creating [GatewaySocket] connections.
abstract class GatewaySocketFactory {
  /// Connects to the given [uri] and returns a [GatewaySocket].
  ///
  /// [pingInterval] arms protocol-level keepalive: the socket answers pings
  /// and aborts once the far end stops responding. Null disables it.
  Future<GatewaySocket> connect(
    Uri uri, {
    Map<String, dynamic>? headers,
    Duration? timeout,
    Duration? pingInterval = const Duration(seconds: 20),
  });
}

/// Default implementation of [GatewaySocket] wrapping a [dart:io.WebSocket].
class IoGatewaySocket implements GatewaySocket {
  final WebSocket _webSocket;

  IoGatewaySocket(this._webSocket);

  @override
  Stream<dynamic> get stream => _webSocket;

  @override
  void send(String data) => _webSocket.add(data);

  @override
  Future<void> close([int? code, String? reason]) => _webSocket.close(code, reason);

  @override
  int? get closeCode => _webSocket.closeCode;

  @override
  String? get closeReason => _webSocket.closeReason;
}

/// Default implementation of [GatewaySocketFactory] using [dart:io.WebSocket.connect].
class IoGatewaySocketFactory implements GatewaySocketFactory {
  const IoGatewaySocketFactory();

  @override
  Future<GatewaySocket> connect(
    Uri uri, {
    Map<String, dynamic>? headers,
    Duration? timeout,
    Duration? pingInterval = const Duration(seconds: 20),
  }) async {
    final customHeaders = headers?.map((k, v) => MapEntry(k, v.toString()));

    final future = WebSocket.connect(
      uri.toString(),
      headers: customHeaders,
    );

    final ws = timeout != null ? await future.timeout(timeout) : await future;
    ws.pingInterval = pingInterval;
    return IoGatewaySocket(ws);
  }
}
