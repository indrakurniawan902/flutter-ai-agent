import 'package:equatable/equatable.dart';

/// Base class for all Hermes Universal Gateway protocol messages.
abstract class GatewayMessage extends Equatable {
  final String type;

  const GatewayMessage(this.type);

  /// Serializes this message to a JSON map.
  Map<String, dynamic> toJson();

  /// Deserializes a [GatewayMessage] from a JSON map based on its type / event.
  factory GatewayMessage.fromJson(Map<String, dynamic> json) {
    final type = (json['type'] ?? json['event'] ?? 'raw').toString().toLowerCase();

    switch (type) {
      case 'auth':
        // If it's an incoming auth status or ack from server:
        if (json.containsKey('status')) {
          final status = json['status']?.toString().toLowerCase();
          if (status == 'authenticated' || status == 'ok' || status == 'success') {
            return GatewayAuthSuccessMessage.fromJson(json);
          } else {
            return GatewayAuthFailureMessage.fromJson(json);
          }
        }
        return GatewayAuthMessage.fromJson(json);

      case 'auth_success':
      case 'auth_ok':
      case 'authenticated':
        return GatewayAuthSuccessMessage.fromJson(json);

      case 'auth_failure':
      case 'unauthorized':
        return GatewayAuthFailureMessage.fromJson(json);

      case 'ping':
        return GatewayPingMessage.fromJson(json);

      case 'pong':
        return GatewayPongMessage.fromJson(json);

      case 'text_delta':
      case 'delta':
        return GatewayTextDeltaMessage.fromJson(json);

      case 'tool_call_request':
      case 'tool_call':
        return GatewayToolCallRequestMessage.fromJson(json);

      case 'tool_call_response':
      case 'tool_result':
        return GatewayToolCallResponseMessage.fromJson(json);

      case 'tool_event':
        return GatewayToolEventMessage.fromJson(json);

      case 'elicitation_request':
        return GatewayElicitationRequestMessage.fromJson(json);

      case 'elicitation_response':
        return GatewayElicitationResponseMessage.fromJson(json);

      case 'chat_message':
      case 'message':
        return GatewayChatMessage.fromJson(json);

      case 'tool_manifest':
      case 'hello':
        return GatewayToolManifestMessage.fromJson(json);

case 'error':
         return GatewayErrorMessage.fromJson(json);

       case 'chat_cancel':
         return GatewayChatCancelMessage.fromJson(json);

       default:
         return GatewayRawMessage(type: type, payload: json);
    }
  }

  @override
  List<Object?> get props => [type];
}

/// Authentication handshake request message sent by the client.
class GatewayAuthMessage extends GatewayMessage {
  final String token;
  final String clientId;
  final String clientVersion;
  final Map<String, dynamic>? deviceInfo;

  const GatewayAuthMessage({
    required this.token,
    this.clientId = 'flutter_client',
    this.clientVersion = '1.0.0',
    this.deviceInfo,
  }) : super('auth');

  factory GatewayAuthMessage.fromJson(Map<String, dynamic> json) {
    return GatewayAuthMessage(
      token: (json['token'] ?? '').toString(),
      clientId: (json['client_id'] ?? json['clientId'] ?? 'flutter_client').toString(),
      clientVersion: (json['client_version'] ?? json['clientVersion'] ?? '1.0.0').toString(),
      deviceInfo: json['device_info'] is Map<String, dynamic>
          ? json['device_info'] as Map<String, dynamic>
          : (json['deviceInfo'] is Map<String, dynamic>
              ? json['deviceInfo'] as Map<String, dynamic>
              : null),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'token': token,
        'client_id': clientId,
        'client_version': clientVersion,
        if (deviceInfo != null) 'device_info': deviceInfo,
      };

  @override
  List<Object?> get props => [type, token, clientId, clientVersion, deviceInfo];
}

/// Authentication success acknowledgment message received from the server.
class GatewayAuthSuccessMessage extends GatewayMessage {
  final String? message;
  final String? sessionId;

  const GatewayAuthSuccessMessage({
    this.message,
    this.sessionId,
  }) : super('auth_success');

  factory GatewayAuthSuccessMessage.fromJson(Map<String, dynamic> json) {
    return GatewayAuthSuccessMessage(
      message: json['message'] as String?,
      sessionId: (json['session_id'] ?? json['sessionId']) as String?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        if (message != null) 'message': message,
        if (sessionId != null) 'session_id': sessionId,
      };

  @override
  List<Object?> get props => [type, message, sessionId];
}

/// Authentication failure message received from the server.
class GatewayAuthFailureMessage extends GatewayMessage {
  final String error;
  final int? code;

  const GatewayAuthFailureMessage({
    required this.error,
    this.code,
  }) : super('auth_failure');

  factory GatewayAuthFailureMessage.fromJson(Map<String, dynamic> json) {
    return GatewayAuthFailureMessage(
      error: (json['error'] ?? json['message'] ?? 'Authentication failed').toString(),
      code: json['code'] is int ? json['code'] as int : int.tryParse(json['code']?.toString() ?? ''),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'error': error,
        if (code != null) 'code': code,
      };

  @override
  List<Object?> get props => [type, error, code];
}

/// Ping heartbeat message.
class GatewayPingMessage extends GatewayMessage {
  final int timestamp;

  GatewayPingMessage({int? timestamp})
      : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch,
        super('ping');

  factory GatewayPingMessage.fromJson(Map<String, dynamic> json) {
    final rawTime = json['timestamp'];
    final ts = rawTime is int
        ? rawTime
        : (int.tryParse(rawTime?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch);
    return GatewayPingMessage(timestamp: ts);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp,
      };

  @override
  List<Object?> get props => [type, timestamp];
}

/// Pong heartbeat reply message.
class GatewayPongMessage extends GatewayMessage {
  final int timestamp;

  GatewayPongMessage({int? timestamp})
      : timestamp = timestamp ?? DateTime.now().millisecondsSinceEpoch,
        super('pong');

  factory GatewayPongMessage.fromJson(Map<String, dynamic> json) {
    final rawTime = json['timestamp'];
    final ts = rawTime is int
        ? rawTime
        : (int.tryParse(rawTime?.toString() ?? '') ?? DateTime.now().millisecondsSinceEpoch);
    return GatewayPongMessage(timestamp: ts);
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'timestamp': timestamp,
      };

  @override
  List<Object?> get props => [type, timestamp];
}

/// Streaming text delta emitted by Hermes during generation.
class GatewayTextDeltaMessage extends GatewayMessage {
  final String delta;
  final String? sessionId;
  final bool isDone;

  const GatewayTextDeltaMessage({
    required this.delta,
    this.sessionId,
    this.isDone = false,
  }) : super('text_delta');

  factory GatewayTextDeltaMessage.fromJson(Map<String, dynamic> json) {
    return GatewayTextDeltaMessage(
      delta: (json['delta'] ?? json['text'] ?? json['content'] ?? '').toString(),
      sessionId: (json['session_id'] ?? json['sessionId']) as String?,
      isDone: json['is_done'] == true || json['done'] == true,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'delta': delta,
        if (sessionId != null) 'session_id': sessionId,
        'is_done': isDone,
      };

  @override
  List<Object?> get props => [type, delta, sessionId, isDone];
}

/// Tool call request message sent by remote Hermes to execute a device tool.
class GatewayToolCallRequestMessage extends GatewayMessage {
  final String id;
  final String tool;
  final Map<String, dynamic> arguments;

  const GatewayToolCallRequestMessage({
    required this.id,
    required this.tool,
    this.arguments = const {},
  }) : super('tool_call_request');

  factory GatewayToolCallRequestMessage.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['call_id'] ?? json['callId'] ?? '').toString();
    final tool = (json['tool'] ?? json['name'] ?? json['tool_name'] ?? '').toString();
    final rawArgs = json['arguments'] ?? json['parameters'] ?? json['params'];
    final Map<String, dynamic> arguments = rawArgs is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawArgs)
        : (rawArgs is Map ? Map<String, dynamic>.from(rawArgs) : <String, dynamic>{});

    return GatewayToolCallRequestMessage(
      id: id,
      tool: tool,
      arguments: arguments,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        'tool': tool,
        'arguments': arguments,
      };

  @override
  List<Object?> get props => [type, id, tool, arguments];
}

/// Tool call execution response sent from the client back to Hermes Gateway.
class GatewayToolCallResponseMessage extends GatewayMessage {
  final String id;
  final Map<String, dynamic>? result;
  final String? error;

  const GatewayToolCallResponseMessage({
    required this.id,
    this.result,
    this.error,
  }) : super('tool_call_response');

  factory GatewayToolCallResponseMessage.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? json['call_id'] ?? json['callId'] ?? '').toString();
    final rawResult = json['result'] ?? json['data'];
    final Map<String, dynamic>? result = rawResult is Map<String, dynamic>
        ? rawResult
        : (rawResult is Map ? Map<String, dynamic>.from(rawResult) : null);
    final error = json['error'] as String?;

    return GatewayToolCallResponseMessage(
      id: id,
      result: result,
      error: error,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'id': id,
        if (result != null) 'result': result,
        if (error != null) 'error': error,
      };

  @override
  List<Object?> get props => [type, id, result, error];
}

/// User chat prompt or assistant message over Gateway transport.
class GatewayChatMessage extends GatewayMessage {
  final String content;
  final String role;
  final Map<String, dynamic>? metadata;

  const GatewayChatMessage({
    required this.content,
    this.role = 'user',
    this.metadata,
  }) : super('chat_message');

  factory GatewayChatMessage.fromJson(Map<String, dynamic> json) {
    return GatewayChatMessage(
      content: (json['content'] ?? json['message'] ?? '').toString(),
      role: (json['role'] ?? 'user').toString(),
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'content': content,
        'role': role,
        if (metadata != null) 'metadata': metadata,
      };

  @override
  List<Object?> get props => [type, content, role, metadata];
}

/// Requests cancellation of the in-flight generation on the remote agent.
class GatewayChatCancelMessage extends GatewayMessage {
  const GatewayChatCancelMessage() : super('chat_cancel');

  factory GatewayChatCancelMessage.fromJson(Map<String, dynamic> json) =>
      const GatewayChatCancelMessage();

  @override
  Map<String, dynamic> toJson() => {'type': 'chat_cancel'};

  // match the props/== style of GatewayChatMessage (props likely [type])
  @override
  List<Object?> get props => [type];
}

/// General error frame emitted by Gateway.
class GatewayErrorMessage extends GatewayMessage {
  final String message;
  final String? code;

  const GatewayErrorMessage({
    required this.message,
    this.code,
  }) : super('error');

  factory GatewayErrorMessage.fromJson(Map<String, dynamic> json) {
    return GatewayErrorMessage(
      message: (json['message'] ?? json['error'] ?? 'Unknown error').toString(),
      code: json['code']?.toString(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'message': message,
        if (code != null) 'code': code,
      };

  @override
  List<Object?> get props => [type, message, code];
}

/// Fallback message for unrecognized message frames.
class GatewayRawMessage extends GatewayMessage {
  final Map<String, dynamic> payload;

  const GatewayRawMessage({
    required String type,
    required this.payload,
  }) : super(type);

  @override
  Map<String, dynamic> toJson() => payload;

  @override
  List<Object?> get props => [type, payload];
}

/// Tool manifest frame advertising the device's OpenAI-format tool schemas.
///
/// The [tools] list is passed through verbatim: it is exactly the output of
/// `ToolRegistry.getOpenAiToolDefinitions()`. No key rewriting, coercion or
/// re-shaping is performed on either serialization or deserialization.
class GatewayToolManifestMessage extends GatewayMessage {
  final String version;
  final String deviceId;
  final List<Map<String, dynamic>> tools;

  const GatewayToolManifestMessage({
    this.version = 'v1',
    required this.deviceId,
    required this.tools,
  }) : super('tool_manifest');

  factory GatewayToolManifestMessage.fromJson(Map<String, dynamic> json) {
    final rawTools = json['tools'];
    final tools = <Map<String, dynamic>>[];
    if (rawTools is List) {
      for (final tool in rawTools) {
        if (tool is Map) {
          tools.add(Map<String, dynamic>.from(tool));
        }
      }
    }
    return GatewayToolManifestMessage(
      version: (json['version'] ?? 'v1').toString(),
      deviceId: (json['device_id'] ?? json['deviceId'] ?? '').toString(),
      tools: tools,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'version': version,
        'device_id': deviceId,
        'tools': tools,
      };

  @override
  List<Object?> get props => [type, version, deviceId, tools];
}

/// Remote HITL elicitation request sent by Hermes to gate a risky action.
///
/// [riskLevel] is normalized to lowercase. A missing/null value falls back to
/// `'high'`; unknown values are preserved as-is. [fields] is parsed
/// defensively, skipping non-Map entries, mirroring
/// [GatewayToolManifestMessage.tools].
class GatewayElicitationRequestMessage extends GatewayMessage {
  final String requestId;
  final String title;
  final String description;
  final String riskLevel;
  final List<Map<String, dynamic>> fields;

  const GatewayElicitationRequestMessage({
    required this.requestId,
    this.title = '',
    this.description = '',
    this.riskLevel = 'high',
    this.fields = const [],
  }) : super('elicitation_request');

  factory GatewayElicitationRequestMessage.fromJson(Map<String, dynamic> json) {
    final requestId =
        (json['request_id'] ?? json['requestId'] ?? json['id'] ?? '').toString();
    final rawRisk = json['risk_level'] ?? json['riskLevel'];
    final rawFields = json['fields'];
    final fields = <Map<String, dynamic>>[];
    if (rawFields is List) {
      for (final field in rawFields) {
        if (field is Map) {
          fields.add(Map<String, dynamic>.from(field));
        }
      }
    }
    return GatewayElicitationRequestMessage(
      requestId: requestId,
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      riskLevel: rawRisk == null ? 'high' : rawRisk.toString().toLowerCase(),
      fields: fields,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'request_id': requestId,
        'title': title,
        'description': description,
        'risk_level': riskLevel,
        'fields': fields,
      };

  @override
  List<Object?> get props =>
      [type, requestId, title, description, riskLevel, fields];
}

/// Client reply to a [GatewayElicitationRequestMessage], carrying the HITL
/// decision back to Hermes.
class GatewayElicitationResponseMessage extends GatewayMessage {
  final String requestId;
  final String status;
  final bool biometricVerified;

  const GatewayElicitationResponseMessage({
    required this.requestId,
    required this.status,
    this.biometricVerified = false,
  }) : super('elicitation_response');

  factory GatewayElicitationResponseMessage.fromJson(Map<String, dynamic> json) {
    final requestId =
        (json['request_id'] ?? json['requestId'] ?? json['id'] ?? '').toString();
    return GatewayElicitationResponseMessage(
      requestId: requestId,
      status: (json['status'] ?? '').toString(),
      biometricVerified: (json['biometric_verified'] ??
              json['biometricVerified'] ??
              false)
          as bool,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'request_id': requestId,
        'status': status,
        'biometric_verified': biometricVerified,
      };

  @override
  List<Object?> get props => [type, requestId, status, biometricVerified];
}

/// Server-side tool lifecycle telemetry forwarded by the device bridge.
///
/// Additive frame, display-only (no reply expected).
/// No emoji is carried by the protocol.
class GatewayToolEventMessage extends GatewayMessage {
  final String phase;
  final String tool;
  final String label;
  final String toolCallId;
  final String? sessionId;

  const GatewayToolEventMessage({
    this.phase = '',
    this.tool = '',
    this.label = '',
    this.toolCallId = '',
    this.sessionId,
  }) : super('tool_event');

  factory GatewayToolEventMessage.fromJson(Map<String, dynamic> json) {
    final rawSessionId = json['session_id'] ?? json['sessionId'];
    return GatewayToolEventMessage(
      phase: (json['phase'] ?? '').toString(),
      tool: (json['tool'] ?? '').toString(),
      label: (json['label'] ?? '').toString(),
      toolCallId: (json['tool_call_id'] ?? json['toolCallId'] ?? '').toString(),
      sessionId: rawSessionId?.toString(),
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'phase': phase,
        'tool': tool,
        'label': label,
        'tool_call_id': toolCallId,
        if (sessionId != null) 'session_id': sessionId,
      };

  @override
  List<Object?> get props => [type, phase, tool, label, toolCallId, sessionId];
}
