import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_socket.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';

/// Supplies the tool manifest frames advertised to the bridge.
typedef ToolManifestProvider = List<Map<String, dynamic>> Function();

/// Configuration options for [GatewayClient].
class GatewayClientOptions {
  final Duration heartbeatInterval;
  final Duration heartbeatTimeout;
  final Duration authTimeout;
  final Duration connectTimeout;
  final bool autoReconnect;
  final Duration initialReconnectDelay;
  final Duration maxReconnectDelay;
  final double reconnectBackoffFactor;
  final int maxReconnectAttempts;

  const GatewayClientOptions({
    this.heartbeatInterval = const Duration(seconds: 30),
    this.heartbeatTimeout = const Duration(seconds: 10),
    this.authTimeout = const Duration(seconds: 10),
    this.connectTimeout = const Duration(seconds: 15),
    this.autoReconnect = true,
    this.initialReconnectDelay = const Duration(seconds: 1),
    this.maxReconnectDelay = const Duration(seconds: 30),
    this.reconnectBackoffFactor = 1.5,
    this.maxReconnectAttempts = 10,
  });
}

/// Universal bidirectional network client connecting the Flutter app to any remote Hermes Gateway instance.
class GatewayClient implements GatewayClientBase {
  /// Default bridge path used only when a gateway URL carries no path.
  static const String defaultGatewayPath = '/device/ws';

  final GatewaySocketFactory socketFactory;
  final GatewayClientOptions options;
  final ToolManifestProvider? toolManifestProvider;
  final String clientId;

  GatewayConnectionState _state = GatewayConnectionState.disconnected;
  final _stateController = StreamController<GatewayConnectionState>.broadcast();

  final _messageController = StreamController<GatewayMessage>.broadcast();
  final _textDeltaController = StreamController<GatewayTextDeltaMessage>.broadcast();
  final _toolCallRequestController = StreamController<GatewayToolCallRequestMessage>.broadcast();

  GatewaySocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;

  String? _currentGatewayUrl;
  String? _currentToken;
  bool _manuallyDisconnected = false;
  int _reconnectAttempts = 0;

  Timer? _reconnectTimer;
  Timer? _heartbeatTimer;
  Timer? _watchdogTimer;
  Timer? _authTimer;

  bool _disposed = false;

  GatewayClient({
    GatewaySocketFactory? socketFactory,
    this.options = const GatewayClientOptions(),
    this.toolManifestProvider,
    this.clientId = 'flutter_client',
  }) : socketFactory = socketFactory ?? const IoGatewaySocketFactory();

  /// Current connection state.
  @override
  GatewayConnectionState get state => _state;

  /// Stream of connection state transitions.
  @override
  Stream<GatewayConnectionState> get stateStream => _stateController.stream;

  /// Stream of all incoming [GatewayMessage] events.
  @override
  Stream<GatewayMessage> get messageStream => _messageController.stream;

  /// Stream of incoming text deltas from streaming generation.
  @override
  Stream<GatewayTextDeltaMessage> get textDeltaStream => _textDeltaController.stream;

  /// Stream of incoming tool call requests sent from the server.
  @override
  Stream<GatewayToolCallRequestMessage> get toolCallRequestStream =>
      _toolCallRequestController.stream;

  /// Normalizes a user-provided gateway URL into a valid WebSocket [Uri].
  ///
  /// Only the scheme is rewritten. A URL that already carries a path is passed
  /// through completely unchanged - no double-append, no `/ws` override and no
  /// trailing-slash rewriting. An empty or `/` path falls back to
  /// [defaultGatewayPath], the real bridge route.
  static Uri normalizeGatewayUri(String rawUrl) {
    var url = rawUrl.trim();

    // Check scheme and convert http(s) to ws(s)
    if (url.startsWith('http://')) {
      url = 'ws://${url.substring(7)}';
    } else if (url.startsWith('https://')) {
      url = 'wss://${url.substring(8)}';
    } else if (!url.startsWith('ws://') && !url.startsWith('wss://')) {
      url = 'ws://$url';
    }

    final uri = Uri.parse(url);

    // If path is empty, append the documented bridge default endpoint.
    if (uri.path.isEmpty || uri.path == '/') {
      return uri.replace(path: defaultGatewayPath);
    }

    return uri;
  }

  /// Connects using an active [ServerProfile].
  @override
  Future<void> connectWithProfile(ServerProfile profile) {
    return connect(profile.gatewayUrl, token: profile.token);
  }

  /// Connects to the Hermes Gateway at [gatewayUrl] using authentication [token].
  @override
  Future<void> connect(String gatewayUrl, {String? token}) async {
    if (_disposed) return;

    _manuallyDisconnected = false;
    _currentGatewayUrl = gatewayUrl;
    _currentToken = token;

    _cancelTimers();
    await _cleanUpSocket();

    _setState(GatewayConnectionState.connecting);

    try {
      final uri = normalizeGatewayUri(gatewayUrl);
      final socket = await socketFactory.connect(
        uri,
        timeout: options.connectTimeout,
      );

      if (_manuallyDisconnected || _disposed) {
        await socket.close();
        return;
      }

      _socket = socket;
      _socketSubscription = socket.stream.listen(
        _handleIncomingData,
        onDone: _handleSocketDone,
        onError: _handleSocketError,
        cancelOnError: true,
      );

      // Immediately send authentication handshake frame
      final authMessage = GatewayAuthMessage(
        token: token ?? '',
        clientId: clientId,
      );
      send(authMessage);

      // Start auth timeout timer
      _authTimer?.cancel();
      _authTimer = Timer(options.authTimeout, _handleAuthTimeout);
    } catch (error) {
      _handleSocketError(error);
    }
  }

  /// Handles incoming data frame from the WebSocket.
  void _handleIncomingData(dynamic raw) {
    try {
      Map<String, dynamic> jsonMap;
      if (raw is String) {
        jsonMap = jsonDecode(raw) as Map<String, dynamic>;
      } else if (raw is Map<String, dynamic>) {
        jsonMap = raw;
      } else {
        return;
      }

      final message = GatewayMessage.fromJson(jsonMap);

      if (_state == GatewayConnectionState.connecting) {
        if (message is GatewayAuthSuccessMessage) {
          _authTimer?.cancel();
          _authTimer = null;
          _reconnectAttempts = 0;
          _setState(GatewayConnectionState.connected);
          _startHeartbeat();
          _sendToolManifest();
          _messageController.add(message);
          return;
        } else if (message is GatewayAuthFailureMessage) {
          _authTimer?.cancel();
          _authTimer = null;
          _manuallyDisconnected = true; // Never auto-reconnect on auth rejection
          _cleanUpSocket();
          _setState(GatewayConnectionState.disconnected);
          _messageController.add(message);
          return;
        }
      }

      // If connected:
      if (message is GatewayPingMessage) {
        send(GatewayPongMessage(timestamp: message.timestamp));
      } else if (message is GatewayPongMessage) {
        _watchdogTimer?.cancel();
        _watchdogTimer = null;
      } else if (message is GatewayTextDeltaMessage) {
        _textDeltaController.add(message);
      } else if (message is GatewayToolCallRequestMessage) {
        _toolCallRequestController.add(message);
      }

      _messageController.add(message);
    } catch (_) {
      // Ignore unparseable frames
    }
  }

  /// Sends the tool manifest frame right after a successful authentication.
  ///
  /// The manifest is advertised verbatim: whatever the injected provider
  /// returns, unfiltered and unrenamed. When no provider is configured the
  /// handshake proceeds without a manifest; when the provider throws, the
  /// handshake still completes (the bridge's manifest deadline handles the
  /// missing frame, a broken provider must never abort the socket).
  void _sendToolManifest() {
    final provider = toolManifestProvider;
    if (provider == null) return;
    try {
      send(GatewayToolManifestMessage(deviceId: clientId, tools: provider()));
    } catch (_) {
      // A broken manifest provider must never abort the handshake.
    }
  }

  /// Starts the periodic heartbeat ping timer.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(options.heartbeatInterval, (_) {
      if (_state != GatewayConnectionState.connected) return;

      send(GatewayPingMessage());

      // Only start watchdog if one is not already pending for an unanswered ping
      _watchdogTimer ??= Timer(options.heartbeatTimeout, () {
        // Watchdog expired: server failed to respond to heartbeat
        _cleanUpSocket();
        _triggerReconnect();
      });
    });
  }

  /// Handles authentication timeout if the gateway never responded to auth frame.
  void _handleAuthTimeout() {
    if (_state != GatewayConnectionState.connecting) return;
    _cleanUpSocket();
    _triggerReconnect();
  }

  /// Handles unexpected socket closure.
  void _handleSocketDone() {
    _cleanUpSocket();
    if (!_manuallyDisconnected && options.autoReconnect) {
      _triggerReconnect();
    } else {
      _setState(GatewayConnectionState.disconnected);
    }
  }

  /// Handles socket stream error.
  void _handleSocketError(dynamic error) {
    _cleanUpSocket();
    if (!_manuallyDisconnected && options.autoReconnect) {
      _triggerReconnect();
    } else {
      _setState(GatewayConnectionState.disconnected);
    }
  }

  /// Initiates automatic reconnection with exponential backoff.
  void _triggerReconnect() {
    if (_manuallyDisconnected || _disposed) {
      _setState(GatewayConnectionState.disconnected);
      return;
    }

    _setState(GatewayConnectionState.reconnecting);
    _reconnectAttempts++;

    if (options.maxReconnectAttempts > 0 &&
        _reconnectAttempts > options.maxReconnectAttempts) {
      _setState(GatewayConnectionState.disconnected);
      return;
    }

    final delayMs = (options.initialReconnectDelay.inMilliseconds *
            pow(options.reconnectBackoffFactor, _reconnectAttempts - 1))
        .round();
    final cappedDelayMs = min(delayMs, options.maxReconnectDelay.inMilliseconds);
    final delay = Duration(milliseconds: cappedDelayMs);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (!_manuallyDisconnected && !_disposed && _currentGatewayUrl != null) {
        connect(_currentGatewayUrl!, token: _currentToken);
      }
    });
  }

  /// Sends a structured [GatewayMessage].
  @override
  void send(GatewayMessage message) {
    sendJson(message.toJson());
  }

  /// Sends a raw JSON map across the WebSocket.
  @override
  void sendJson(Map<String, dynamic> json) {
    if (_socket != null) {
      _socket!.send(jsonEncode(json));
    }
  }

  /// Sends a tool execution result frame back to Hermes Gateway.
  @override
  void sendToolCallResponse({
    required String callId,
    Map<String, dynamic>? result,
    String? error,
  }) {
    send(GatewayToolCallResponseMessage(
      id: callId,
      result: result,
      error: error,
    ));
  }

  /// Sends a chat message frame across the gateway connection.
  @override
  void sendChatMessage(
    String content, {
    String role = 'user',
    Map<String, dynamic>? metadata,
  }) {
    send(GatewayChatMessage(
      content: content,
      role: role,
      metadata: metadata,
    ));
  }

  /// Disconnects the socket and disables auto-reconnection.
  @override
  Future<void> disconnect({String? reason}) async {
    _manuallyDisconnected = true;
    _cancelTimers();
    await _cleanUpSocket();
    _setState(GatewayConnectionState.disconnected);
  }

  /// Updates connection state and notifies stream listeners.
  void _setState(GatewayConnectionState newState) {
    if (_state == newState) return;
    _state = newState;
    if (!_stateController.isClosed) {
      _stateController.add(newState);
    }
  }

  /// Cancels all active timers.
  void _cancelTimers() {
    _authTimer?.cancel();
    _authTimer = null;
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    _watchdogTimer?.cancel();
    _watchdogTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  /// Cleans up current socket and subscription.
  Future<void> _cleanUpSocket() async {
    _cancelTimers();
    unawaited(_socketSubscription?.cancel());
    _socketSubscription = null;
    try {
      unawaited(_socket?.close());
    } catch (_) {}
    _socket = null;
  }

  /// Disposes resources, closes streams, and disconnects.
  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect(reason: 'Client disposed');
    await _stateController.close();
    await _messageController.close();
    await _textDeltaController.close();
    await _toolCallRequestController.close();
  }
}
