import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';

void main() {
  group('GatewayMessage', () {
    test('GatewayAuthMessage serializes and deserializes correctly', () {
      final msg = GatewayAuthMessage(
        token: 'secret_token_123',
        clientId: 'flutter_client',
        clientVersion: '1.0.0',
        deviceInfo: const {'platform': 'android'},
      );

      final json = msg.toJson();
      expect(json['type'], 'auth');
      expect(json['token'], 'secret_token_123');
      expect(json['client_id'], 'flutter_client');
      expect(json['client_version'], '1.0.0');
      expect(json['device_info'], {'platform': 'android'});

      final parsed = GatewayMessage.fromJson(json);
      expect(parsed, isA<GatewayAuthMessage>());
      final authMsg = parsed as GatewayAuthMessage;
      expect(authMsg.token, 'secret_token_123');
      expect(authMsg.clientId, 'flutter_client');
      expect(authMsg.clientVersion, '1.0.0');
      expect(authMsg.deviceInfo, {'platform': 'android'});
    });

    test('GatewayAuthSuccessMessage serializes and deserializes correctly', () {
      final msg = const GatewayAuthSuccessMessage(
        message: 'Welcome',
        sessionId: 'session_abc',
      );

      final json = msg.toJson();
      expect(json['type'], 'auth_success');
      expect(json['message'], 'Welcome');
      expect(json['session_id'], 'session_abc');

      final parsed = GatewayMessage.fromJson(json);
      expect(parsed, isA<GatewayAuthSuccessMessage>());
      final success = parsed as GatewayAuthSuccessMessage;
      expect(success.message, 'Welcome');
      expect(success.sessionId, 'session_abc');
    });

    test('GatewayAuthFailureMessage serializes and deserializes correctly', () {
      final msg = const GatewayAuthFailureMessage(
        error: 'Invalid authentication token',
        code: 401,
      );

      final json = msg.toJson();
      expect(json['type'], 'auth_failure');
      expect(json['error'], 'Invalid authentication token');
      expect(json['code'], 401);

      final parsed = GatewayMessage.fromJson(json);
      expect(parsed, isA<GatewayAuthFailureMessage>());
      final failure = parsed as GatewayAuthFailureMessage;
      expect(failure.error, 'Invalid authentication token');
      expect(failure.code, 401);
    });

    test('GatewayPingMessage and GatewayPongMessage serialize and deserialize', () {
      final now = DateTime.now().millisecondsSinceEpoch;
      final ping = GatewayPingMessage(timestamp: now);
      final pingJson = ping.toJson();
      expect(pingJson['type'], 'ping');
      expect(pingJson['timestamp'], now);

      final parsedPing = GatewayMessage.fromJson(pingJson);
      expect(parsedPing, isA<GatewayPingMessage>());
      expect((parsedPing as GatewayPingMessage).timestamp, now);

      final pong = GatewayPongMessage(timestamp: now);
      final pongJson = pong.toJson();
      expect(pongJson['type'], 'pong');
      expect(pongJson['timestamp'], now);

      final parsedPong = GatewayMessage.fromJson(pongJson);
      expect(parsedPong, isA<GatewayPongMessage>());
      expect((parsedPong as GatewayPongMessage).timestamp, now);
    });

    test('GatewayTextDeltaMessage serializes and deserializes streaming deltas', () {
      final msg = const GatewayTextDeltaMessage(
        delta: 'Hello from Hermes!',
        sessionId: 'sess_1',
        isDone: false,
      );

      final json = msg.toJson();
      expect(json['type'], 'text_delta');
      expect(json['delta'], 'Hello from Hermes!');
      expect(json['session_id'], 'sess_1');
      expect(json['is_done'], isFalse);

      final parsed = GatewayMessage.fromJson(json);
      expect(parsed, isA<GatewayTextDeltaMessage>());
      final delta = parsed as GatewayTextDeltaMessage;
      expect(delta.delta, 'Hello from Hermes!');
      expect(delta.sessionId, 'sess_1');
      expect(delta.isDone, isFalse);
    });

    test('GatewayToolCallRequestMessage parses tool call frames with aliases', () {
      // Standard snake_case
      final json1 = {
        'type': 'tool_call_request',
        'id': 'call_1',
        'tool': 'device_status',
        'arguments': {'accuracy': 'high'},
      };
      final parsed1 = GatewayMessage.fromJson(json1);
      expect(parsed1, isA<GatewayToolCallRequestMessage>());
      final req1 = parsed1 as GatewayToolCallRequestMessage;
      expect(req1.id, 'call_1');
      expect(req1.tool, 'device_status');
      expect(req1.arguments, {'accuracy': 'high'});

      // Aliases: call_id, name, parameters
      final json2 = {
        'event': 'tool_call_request',
        'call_id': 'call_2',
        'name': 'get_location',
        'parameters': {'accuracy': 'low'},
      };
      final parsed2 = GatewayMessage.fromJson(json2);
      expect(parsed2, isA<GatewayToolCallRequestMessage>());
      final req2 = parsed2 as GatewayToolCallRequestMessage;
      expect(req2.id, 'call_2');
      expect(req2.tool, 'get_location');
      expect(req2.arguments, {'accuracy': 'low'});
    });

    test('GatewayToolCallResponseMessage serializes and deserializes', () {
      final msg = const GatewayToolCallResponseMessage(
        id: 'call_123',
        result: {'battery': 85, 'charging': true},
        error: null,
      );

      final json = msg.toJson();
      expect(json['type'], 'tool_call_response');
      expect(json['id'], 'call_123');
      expect(json['result'], {'battery': 85, 'charging': true});
      expect(json['error'], isNull);

      final parsed = GatewayMessage.fromJson(json);
      expect(parsed, isA<GatewayToolCallResponseMessage>());
      final resp = parsed as GatewayToolCallResponseMessage;
      expect(resp.id, 'call_123');
      expect(resp.result, {'battery': 85, 'charging': true});
      expect(resp.error, isNull);
    });

    test('GatewayChatMessage serializes and deserializes', () {
      final msg = const GatewayChatMessage(
        content: 'Check device battery',
        role: 'user',
      );

      final json = msg.toJson();
      expect(json['type'], 'chat_message');
      expect(json['content'], 'Check device battery');
      expect(json['role'], 'user');

      final parsed = GatewayMessage.fromJson(json);
      expect(parsed, isA<GatewayChatMessage>());
      final chat = parsed as GatewayChatMessage;
      expect(chat.content, 'Check device battery');
      expect(chat.role, 'user');
    });

    test('GatewayErrorMessage serializes and deserializes', () {
      final msg = const GatewayErrorMessage(
        message: 'Something went wrong',
        code: 'internal_error',
      );

      final json = msg.toJson();
      expect(json['type'], 'error');
      expect(json['message'], 'Something went wrong');
      expect(json['code'], 'internal_error');

      final parsed = GatewayMessage.fromJson(json);
      expect(parsed, isA<GatewayErrorMessage>());
      final err = parsed as GatewayErrorMessage;
      expect(err.message, 'Something went wrong');
      expect(err.code, 'internal_error');
    });

    test('GatewayToolManifestMessage serializes tools verbatim', () {
      final tools = <Map<String, dynamic>>[
        {
          'type': 'function',
          'function': {
            'name': 'get_battery_level',
            'description': 'Returns the device battery level.',
            'parameters': {
              'type': 'object',
              'properties': {
                'include_percent': {'type': 'boolean'},
              },
              'required': <String>['include_percent'],
            },
          },
        },
      ];

      final msg = GatewayToolManifestMessage(
        deviceId: 'device_123',
        tools: tools,
      );

      final json = msg.toJson();
      expect(json['type'], 'tool_manifest');
      expect(json['version'], 'v1');
      expect(json['device_id'], 'device_123');
      expect(json['tools'], tools);

      final serializedTools = json['tools'] as List<dynamic>;
      final function =
          (serializedTools.first as Map<String, dynamic>)['function'];
      expect(
        (function as Map<String, dynamic>)['parameters'],
        {
          'type': 'object',
          'properties': {
            'include_percent': {'type': 'boolean'},
          },
          'required': <String>['include_percent'],
        },
      );
    });

    test('GatewayToolManifestMessage round trips through fromJson', () {
      final msg = GatewayToolManifestMessage(
        deviceId: 'device_123',
        tools: <Map<String, dynamic>>[
          {
            'type': 'function',
            'function': {
              'name': 'get_battery_level',
              'description': 'Returns the device battery level.',
              'parameters': {
                'type': 'object',
                'properties': {
                  'include_percent': {'type': 'boolean'},
                },
              },
            },
          },
        ],
      );

      final parsed = GatewayMessage.fromJson(msg.toJson());
      expect(parsed, isA<GatewayToolManifestMessage>());
      final manifest = parsed as GatewayToolManifestMessage;
      expect(manifest.version, msg.version);
      expect(manifest.deviceId, msg.deviceId);
      expect(manifest.tools, msg.tools);
      expect(manifest, msg);
    });

    test('hello alias parses into a GatewayToolManifestMessage', () {
      final json = {
        'type': 'hello',
        'version': 'v1',
        'device_id': 'device_123',
        'tools': <Map<String, dynamic>>[
          {
            'type': 'function',
            'function': {
              'name': 'get_battery_level',
              'description': 'Returns the device battery level.',
              'parameters': {'type': 'object'},
            },
          },
        ],
      };

      final parsed = GatewayMessage.fromJson(json);
      expect(parsed, isA<GatewayToolManifestMessage>());
      final manifest = parsed as GatewayToolManifestMessage;
      expect(manifest.type, 'tool_manifest');
      expect(manifest.version, 'v1');
      expect(manifest.deviceId, 'device_123');
      expect(manifest.tools, hasLength(1));
    });

    test('GatewayElicitationRequestMessage parses a full frame', () {
      final json = {
        'type': 'elicitation_request',
        'request_id': 'elicit_1',
        'title': 'Delete files',
        'description': 'This will remove 3 files',
        'risk_level': 'HIGH',
        'fields': [
          {'name': 'confirm', 'type': 'boolean'},
          'not-a-map',
          42,
        ],
      };

      final parsed = GatewayMessage.fromJson(json);
      expect(parsed, isA<GatewayElicitationRequestMessage>());
      final msg = parsed as GatewayElicitationRequestMessage;
      expect(msg.type, 'elicitation_request');
      expect(msg.requestId, 'elicit_1');
      expect(msg.title, 'Delete files');
      expect(msg.description, 'This will remove 3 files');
      expect(msg.riskLevel, 'high');
      expect(msg.fields, hasLength(1));
      expect(msg.fields.first, {'name': 'confirm', 'type': 'boolean'});
    });

    test('GatewayElicitationRequestMessage falls back to camelCase requestId',
        () {
      final json = {
        'type': 'elicitation_request',
        'requestId': 'elicit_camel',
      };

      final msg = GatewayElicitationRequestMessage.fromJson(json);
      expect(msg.requestId, 'elicit_camel');
      expect(msg.riskLevel, 'high');
      expect(msg.fields, isEmpty);
    });

    test('GatewayElicitationRequestMessage id fallback and null risk default',
        () {
      final json = {
        'type': 'elicitation_request',
        'id': 'elicit_id',
        'risk_level': null,
      };

      final msg = GatewayElicitationRequestMessage.fromJson(json);
      expect(msg.requestId, 'elicit_id');
      expect(msg.riskLevel, 'high');
    });

    test('GatewayElicitationRequestMessage keeps unknown risk as-is', () {
      final json = {
        'type': 'elicitation_request',
        'request_id': 'elicit_2',
        'risk_level': 'Critical',
      };

      final msg = GatewayElicitationRequestMessage.fromJson(json);
      expect(msg.riskLevel, 'critical');
    });

    test('GatewayElicitationRequestMessage round-trips via toJson', () {
      const msg = GatewayElicitationRequestMessage(
        requestId: 'elicit_rt',
        title: 'T',
        description: 'D',
        riskLevel: 'medium',
        fields: [
          {'name': 'x'},
        ],
      );

      final json = msg.toJson();
      expect(json['type'], 'elicitation_request');
      expect(json['request_id'], 'elicit_rt');
      expect(json['risk_level'], 'medium');
      expect(json['fields'], [{'name': 'x'}]);

      final parsed = GatewayMessage.fromJson(json);
      expect(parsed, msg);
    });

    test('GatewayElicitationResponseMessage toJson emits snake_case shape', () {
      const msg = GatewayElicitationResponseMessage(
        requestId: 'elicit_9',
        status: 'approved',
        biometricVerified: true,
      );

      final json = msg.toJson();
      expect(json['type'], 'elicitation_response');
      expect(json['request_id'], 'elicit_9');
      expect(json['status'], 'approved');
      expect(json['biometric_verified'], true);
    });

    test('GatewayElicitationResponseMessage parses and defaults biometric', () {
      final json = {
        'type': 'elicitation_response',
        'request_id': 'elicit_10',
        'status': 'rejected',
      };

      final parsed = GatewayMessage.fromJson(json);
      expect(parsed, isA<GatewayElicitationResponseMessage>());
      final msg = parsed as GatewayElicitationResponseMessage;
      expect(msg.requestId, 'elicit_10');
      expect(msg.status, 'rejected');
      expect(msg.biometricVerified, false);
    });

    test('GatewayRawMessage handles unknown types', () {
      final json = {
        'type': 'custom_event',
        'foo': 'bar',
      };

      final parsed = GatewayMessage.fromJson(json);
      expect(parsed, isA<GatewayRawMessage>());
      final raw = parsed as GatewayRawMessage;
      expect(raw.type, 'custom_event');
      expect(raw.payload, json);
    });
  });
}
