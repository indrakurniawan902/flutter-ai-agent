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
}

/// Factory for creating [GatewaySocket] connections.
abstract class GatewaySocketFactory {
  /// Connects to the given [uri] and returns a [GatewaySocket].
  Future<GatewaySocket> connect(
    Uri uri, {
    Map<String, dynamic>? headers,
    Duration? timeout,
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
}

/// Default implementation of [GatewaySocketFactory] using [dart:io.WebSocket.connect].
class IoGatewaySocketFactory implements GatewaySocketFactory {
  const IoGatewaySocketFactory();

  @override
  Future<GatewaySocket> connect(
    Uri uri, {
    Map<String, dynamic>? headers,
    Duration? timeout,
  }) async {
    final customHeaders = headers?.map((k, v) => MapEntry(k, v.toString()));

    final future = WebSocket.connect(
      uri.toString(),
      headers: customHeaders,
    );

    final ws = timeout != null ? await future.timeout(timeout) : await future;
    return IoGatewaySocket(ws);
  }
}
