import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_client.dart';
import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_socket.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';

class MockGatewaySocket extends Mock implements GatewaySocket {}
class MockGatewaySocketFactory extends Mock implements GatewaySocketFactory {}

/// Captures every `debugPrint` line emitted while [body] runs, then restores
/// the original print target even if [body] throws.
Future<List<String>> captureDebugPrint(Future<void> Function() body) async {
  final lines = <String>[];
  final previous = debugPrint;
  debugPrint = (String? message, {int? wrapWidth}) {
    lines.add(message ?? '');
  };
  try {
    await body();
  } finally {
    debugPrint = previous;
  }
  return lines;
}

void main() {
  late MockGatewaySocketFactory mockSocketFactory;
  late MockGatewaySocket mockSocket;
  late StreamController<dynamic> socketStreamController;
  late List<String> sentFrames;
  late GatewayClient client;

  setUpAll(() {
    registerFallbackValue(Uri.parse('ws://localhost:18789/ws'));
  });

  setUp(() {
    mockSocketFactory = MockGatewaySocketFactory();
    mockSocket = MockGatewaySocket();
    socketStreamController = StreamController<dynamic>.broadcast();
    sentFrames = [];

    when(() => mockSocket.stream).thenAnswer((_) => socketStreamController.stream);
    when(() => mockSocket.send(any())).thenAnswer((invocation) {
      final frame = invocation.positionalArguments[0] as String;
      sentFrames.add(frame);
    });
    when(() => mockSocket.close(any(), any())).thenAnswer((_) async {});

    when(() => mockSocketFactory.connect(
          any(),
          headers: any(named: 'headers'),
          timeout: any(named: 'timeout'),
          pingInterval: any(named: 'pingInterval'),
        )).thenAnswer((_) async => mockSocket);

    client = GatewayClient(
      socketFactory: mockSocketFactory,
      options: const GatewayClientOptions(
        heartbeatInterval: Duration(milliseconds: 50),
        heartbeatTimeout: Duration(milliseconds: 100),
        authTimeout: Duration(milliseconds: 100),
        connectTimeout: Duration(milliseconds: 100),
        initialReconnectDelay: Duration(milliseconds: 20),
        maxReconnectDelay: Duration(milliseconds: 50),
        reconnectBackoffFactor: 1.5,
      ),
    );
  });

  tearDown(() async {
    await client.dispose();
    if (!socketStreamController.isClosed) {
      await socketStreamController.close();
    }
  });

  group('GatewayClient - Initialization & URL Normalization', () {
    test('initial state is disconnected', () {
      expect(client.state, GatewayConnectionState.disconnected);
      expect(client.state.isDisconnected, isTrue);
    });

    test('normalizes http/https/ws/wss URLs correctly', () async {
      final testCases = [
        {'input': 'http://192.168.1.50:18789', 'expected': 'ws://192.168.1.50:18789/device/ws'},
        {'input': 'https://vps.example.com:18789', 'expected': 'wss://vps.example.com:18789/device/ws'},
        {'input': 'ws://example.com/custom', 'expected': 'ws://example.com/custom'},
        {'input': 'wss://example.com/ws', 'expected': 'wss://example.com/ws'},
        {'input': 'example.com:18789', 'expected': 'ws://example.com:18789/device/ws'},
      ];

      for (final tc in testCases) {
        final uri = GatewayClient.normalizeGatewayUri(tc['input']!);
        expect(uri.toString(), tc['expected']);
      }
    });

    test('passes through URLs that already carry a path without double-append', () {
      final testCases = [
        {
          'input': 'https://hermes.indra-developer.my.id/device/ws',
          'expected': 'wss://hermes.indra-developer.my.id/device/ws',
        },
        {'input': 'ws://example.com/custom/ws', 'expected': 'ws://example.com/custom/ws'},
      ];

      for (final tc in testCases) {
        final uri = GatewayClient.normalizeGatewayUri(tc['input']!);
        expect(uri.toString(), tc['expected']);
        expect(uri.path, Uri.parse(tc['expected']!).path);
      }
    });
  });

  group('GatewayClient - Connection & Auth Handshake', () {
    test('connect establishes socket connection and sends auth frame', () async {
      final stateHistory = <GatewayConnectionState>[];
      final sub = client.stateStream.listen(stateHistory.add);

      await client.connect('http://localhost:18789', token: 'test_token_123');

      expect(client.state, GatewayConnectionState.connecting);
      verify(() => mockSocketFactory.connect(
            Uri.parse('ws://localhost:18789/device/ws'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
            pingInterval: any(named: 'pingInterval'),
          )).called(1);

      expect(sentFrames.length, 1);
      final authJson = jsonDecode(sentFrames.first) as Map<String, dynamic>;
      expect(authJson['type'], 'auth');
      expect(authJson['token'], 'test_token_123');

      await sub.cancel();
    });

    test('connectWithProfile connects using profile gatewayUrl and token', () async {
      const profile = ServerProfile(
        id: 'prof_1',
        name: 'My Server',
        gatewayUrl: 'https://vps.example.com:18789',
        token: 'profile_token_456',
        isActive: true,
      );

      await client.connectWithProfile(profile);

      expect(client.state, GatewayConnectionState.connecting);
      verify(() => mockSocketFactory.connect(
            Uri.parse('wss://vps.example.com:18789/device/ws'),
            headers: any(named: 'headers'),
            timeout: any(named: 'timeout'),
            pingInterval: any(named: 'pingInterval'),
          )).called(1);

      expect(sentFrames.length, 1);
      final authJson = jsonDecode(sentFrames.first) as Map<String, dynamic>;
      expect(authJson['type'], 'auth');
      expect(authJson['token'], 'profile_token_456');
    });

    test('auth success transitions state to connected and starts heartbeat', () async {
      final stateHistory = <GatewayConnectionState>[];
      final sub = client.stateStream.listen(stateHistory.add);

      await client.connect('ws://localhost:18789/ws', token: 'token123');
      expect(client.state, GatewayConnectionState.connecting);

      // Server emits auth_success
      socketStreamController.add(jsonEncode({
        'type': 'auth_success',
        'session_id': 'sess_1',
      }));

      await pumpEventQueue();

      expect(client.state, GatewayConnectionState.connected);
      expect(client.state.isConnected, isTrue);

      await sub.cancel();
    });

    test('auth failure transitions state to disconnected and does not reconnect', () async {
      final stateHistory = <GatewayConnectionState>[];
      final sub = client.stateStream.listen(stateHistory.add);

      await client.connect('ws://localhost:18789/ws', token: 'bad_token');
      expect(client.state, GatewayConnectionState.connecting);

      // Server emits auth_failure
      socketStreamController.add(jsonEncode({
        'type': 'auth_failure',
        'error': 'Invalid token',
        'code': 401,
      }));

      await pumpEventQueue();

      expect(client.state, GatewayConnectionState.disconnected);

      // Wait a bit to verify no reconnect happens
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(client.state, GatewayConnectionState.disconnected);
      verify(() => mockSocketFactory.connect(any(), headers: any(named: 'headers'), timeout: any(named: 'timeout'), pingInterval: any(named: 'pingInterval'))).called(1);

      await sub.cancel();
    });

    test('auth timeout triggers reconnect', () async {
      // Create a fast authTimeout client
      final fastClient = GatewayClient(
        socketFactory: mockSocketFactory,
        options: const GatewayClientOptions(
          authTimeout: Duration(milliseconds: 30),
          initialReconnectDelay: Duration(milliseconds: 20),
          maxReconnectDelay: Duration(milliseconds: 40),
          autoReconnect: true,
        ),
      );

      final stateHistory = <GatewayConnectionState>[];
      final sub = fastClient.stateStream.listen(stateHistory.add);

      await fastClient.connect('ws://localhost:18789/ws', token: 'token123');
      expect(fastClient.state, GatewayConnectionState.connecting);

      // Don't send auth response, let it time out
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Should transition to reconnecting
      expect(stateHistory.contains(GatewayConnectionState.reconnecting), isTrue);

      await sub.cancel();
      await fastClient.dispose();
    });
  });

  group('GatewayClient - Ping / Pong Heartbeat', () {
    test('sends periodic ping frames when connected', () async {
      await client.connect('ws://localhost:18789/ws', token: 'token123');

      // Authenticate
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      sentFrames.clear();

      // Wait for heartbeat interval (50ms)
      await Future<void>.delayed(const Duration(milliseconds: 70));

      expect(sentFrames.isNotEmpty, isTrue);
      final pingJson = jsonDecode(sentFrames.first) as Map<String, dynamic>;
      expect(pingJson['type'], 'ping');
    });

    test('automatically responds with pong when server sends ping', () async {
      await client.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      sentFrames.clear();

      // Server sends ping
      socketStreamController.add(jsonEncode({
        'type': 'ping',
        'timestamp': 9999,
      }));

      await pumpEventQueue();

      expect(sentFrames.length, 1);
      final pongJson = jsonDecode(sentFrames.first) as Map<String, dynamic>;
      expect(pongJson['type'], 'pong');
      expect(pongJson['timestamp'], 9999);
    });

    test('heartbeat watchdog drops connection and reconnects when no pong received', () async {
      final fastClient = GatewayClient(
        socketFactory: mockSocketFactory,
        options: const GatewayClientOptions(
          heartbeatInterval: Duration(milliseconds: 30),
          heartbeatTimeout: Duration(milliseconds: 40),
          initialReconnectDelay: Duration(milliseconds: 20),
          autoReconnect: true,
        ),
      );

      final stateHistory = <GatewayConnectionState>[];
      final sub = fastClient.stateStream.listen(stateHistory.add);

      await fastClient.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      expect(fastClient.state, GatewayConnectionState.connected);

      // Wait for ping to fire and pong timeout to trigger
      await Future<void>.delayed(const Duration(milliseconds: 160));

      expect(stateHistory.contains(GatewayConnectionState.reconnecting), isTrue);

      await sub.cancel();
      await fastClient.dispose();
    });

    test('emits text_delta events to messageStream and textDeltaStream', () async {
      await client.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      final messages = <GatewayMessage>[];
      final deltas = <GatewayTextDeltaMessage>[];

      final sub1 = client.messageStream.listen(messages.add);
      final sub2 = client.textDeltaStream.listen(deltas.add);

      // Server sends streaming text delta
      socketStreamController.add(jsonEncode({
        'type': 'text_delta',
        'delta': 'Hello from Hermes',
        'session_id': 'sess_1',
      }));

      await pumpEventQueue();

      expect(messages.length, 1);
      expect(messages.first, isA<GatewayTextDeltaMessage>());
      expect((messages.first as GatewayTextDeltaMessage).delta, 'Hello from Hermes');

      expect(deltas.length, 1);
      expect(deltas.first.delta, 'Hello from Hermes');
      expect(deltas.first.sessionId, 'sess_1');

      await sub1.cancel();
      await sub2.cancel();
    });

    test('emits tool_call_request events to messageStream and toolCallRequestStream', () async {
      await client.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      final messages = <GatewayMessage>[];
      final toolRequests = <GatewayToolCallRequestMessage>[];

      final sub1 = client.messageStream.listen(messages.add);
      final sub2 = client.toolCallRequestStream.listen(toolRequests.add);

      // Server sends tool call request
      socketStreamController.add(jsonEncode({
        'type': 'tool_call_request',
        'id': 'call_123',
        'tool': 'device_status',
        'arguments': {},
      }));

      await pumpEventQueue();

      expect(messages.length, 1);
      expect(messages.first, isA<GatewayToolCallRequestMessage>());

      expect(toolRequests.length, 1);
      expect(toolRequests.first.id, 'call_123');
      expect(toolRequests.first.tool, 'device_status');

      await sub1.cancel();
      await sub2.cancel();
    });

    test(
        'auto-responds with error when tool_call_request arrives with no toolCallRequestStream listener',
        () async {
      await client.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      // Observe the raw message stream only; leave toolCallRequestStream unlistened.
      final messages = <GatewayMessage>[];
      final sub = client.messageStream.listen(messages.add);

      sentFrames.clear();

      socketStreamController.add(jsonEncode({
        'type': 'tool_call_request',
        'id': 'call_orphan',
        'tool': 'device_status',
        'arguments': {},
      }));

      await pumpEventQueue();

      expect(messages.length, 1);
      expect(messages.first, isA<GatewayToolCallRequestMessage>());

      expect(sentFrames.length, 1);
      final frame = jsonDecode(sentFrames.first) as Map<String, dynamic>;
      expect(frame['type'], 'tool_call_response');
      expect(frame['id'], 'call_orphan');
      expect(frame['error'], 'Device RPC receiver is not listening');

      await sub.cancel();
    });

    test('routes elicitation_request to elicitationRequestStream when listener present',
        () async {
      await client.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      final messages = <GatewayMessage>[];
      final elicitations = <GatewayElicitationRequestMessage>[];

      final sub1 = client.messageStream.listen(messages.add);
      final sub2 = client.elicitationRequestStream.listen(elicitations.add);

      sentFrames.clear();

      socketStreamController.add(jsonEncode({
        'type': 'elicitation_request',
        'request_id': 'elicit_live',
        'title': 'Approve?',
        'risk_level': 'medium',
        'fields': [
          {'name': 'ok'},
        ],
      }));

      await pumpEventQueue();

      expect(elicitations.length, 1);
      expect(elicitations.first.requestId, 'elicit_live');
      expect(elicitations.first.riskLevel, 'medium');

      expect(messages.length, 1);
      expect(messages.first, isA<GatewayElicitationRequestMessage>());

      // Listener present: no auto-response emitted.
      expect(sentFrames, isEmpty);

      await sub1.cancel();
      await sub2.cancel();
    });

    test(
        'auto-rejects elicitation_request when elicitationRequestStream has no listener',
        () async {
      await client.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      // Observe the raw message stream only; leave elicitationRequestStream unlistened.
      final messages = <GatewayMessage>[];
      final sub = client.messageStream.listen(messages.add);

      sentFrames.clear();

      socketStreamController.add(jsonEncode({
        'type': 'elicitation_request',
        'request_id': 'elicit_orphan',
        'title': 'Approve?',
      }));

      await pumpEventQueue();

      expect(messages.length, 1);
      expect(messages.first, isA<GatewayElicitationRequestMessage>());

      expect(sentFrames.length, 1);
      final frame = jsonDecode(sentFrames.first) as Map<String, dynamic>;
      expect(frame['type'], 'elicitation_response');
      expect(frame['request_id'], 'elicit_orphan');
      expect(frame['status'], 'rejected');
      expect(frame['biometric_verified'], false);

      await sub.cancel();
    });
  });

  group('GatewayClient - Outgoing Frames', () {
    test('sendToolCallResponse sends formatted JSON frame', () async {
      await client.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      sentFrames.clear();

      client.sendToolCallResponse(
        callId: 'call_99',
        result: {'battery': 95, 'charging': false},
      );

      expect(sentFrames.length, 1);
      final frame = jsonDecode(sentFrames.first) as Map<String, dynamic>;
      expect(frame['type'], 'tool_call_response');
      expect(frame['id'], 'call_99');
      expect(frame['result'], {'battery': 95, 'charging': false});
      expect(frame.containsKey('error'), isFalse);
    });

    test('sendToolCallResponse with error sends error field', () async {
      await client.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      sentFrames.clear();

      client.sendToolCallResponse(
        callId: 'call_100',
        error: 'Permission denied',
      );

      expect(sentFrames.length, 1);
      final frame = jsonDecode(sentFrames.first) as Map<String, dynamic>;
      expect(frame['type'], 'tool_call_response');
      expect(frame['id'], 'call_100');
      expect(frame['error'], 'Permission denied');
    });

    test('sendChatMessage sends formatted JSON frame', () async {
      await client.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      sentFrames.clear();

      client.sendChatMessage('What is my battery status?');

      expect(sentFrames.length, 1);
      final frame = jsonDecode(sentFrames.first) as Map<String, dynamic>;
      expect(frame['type'], 'chat_message');
      expect(frame['content'], 'What is my battery status?');
      expect(frame['role'], 'user');
    });
  });

  group('GatewayClient - Auto-Reconnect & Socket Drop', () {
    test('reconnects when socket stream closes unexpectedly', () async {
      final stateHistory = <GatewayConnectionState>[];
      final sub = client.stateStream.listen(stateHistory.add);

      await client.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      expect(client.state, GatewayConnectionState.connected);

      // Create a new controller for the second socket connection
      final secondStreamController = StreamController<dynamic>.broadcast();
      final secondMockSocket = MockGatewaySocket();
      when(() => secondMockSocket.stream).thenAnswer((_) => secondStreamController.stream);
      when(() => secondMockSocket.send(any())).thenAnswer((_) {});
      when(() => secondMockSocket.close(any(), any())).thenAnswer((_) async {
        await secondStreamController.close();
      });

      when(() => mockSocketFactory.connect(any(), headers: any(named: 'headers'), timeout: any(named: 'timeout'), pingInterval: any(named: 'pingInterval')))
          .thenAnswer((_) async => secondMockSocket);

      // Simulate unexpected socket drop (e.g. server closes or network drop)
      await socketStreamController.close();

      // Wait for reconnect delay
      await Future<void>.delayed(const Duration(milliseconds: 60));

      // Should have transitioned to reconnecting and attempted connect again
      expect(stateHistory.contains(GatewayConnectionState.reconnecting), isTrue);
      verify(() => mockSocketFactory.connect(any(), headers: any(named: 'headers'), timeout: any(named: 'timeout'), pingInterval: any(named: 'pingInterval'))).called(2);

      // Authenticate second connection
      secondStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      expect(client.state, GatewayConnectionState.connected);

      await sub.cancel();
      await secondStreamController.close();
    });

    test('manual disconnect closes socket and prevents auto-reconnect', () async {
      final stateHistory = <GatewayConnectionState>[];
      final sub = client.stateStream.listen(stateHistory.add);

      await client.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      expect(client.state, GatewayConnectionState.connected);

      await client.disconnect(reason: 'User disconnected');

      expect(client.state, GatewayConnectionState.disconnected);

      // Wait a bit to ensure no reconnect attempts
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(client.state, GatewayConnectionState.disconnected);
      verify(() => mockSocketFactory.connect(any(), headers: any(named: 'headers'), timeout: any(named: 'timeout'), pingInterval: any(named: 'pingInterval'))).called(1);

      await sub.cancel();
    });
  });

  group('GatewayClient - Tool Manifest Handshake', () {
    final fixtureTools = <Map<String, dynamic>>[
      {
        'type': 'function',
        'function': {
          'name': 'device_status',
          'description': 'Reads the device status',
          'parameters': {
            'type': 'object',
            'properties': {
              'detail': {'type': 'boolean', 'description': 'Include detail'},
            },
            'required': <String>[],
          },
        },
      },
      {
        'type': 'function',
        'function': {
          'name': 'read_file',
          'description': 'Reads a file',
          'parameters': {
            'type': 'object',
            'properties': <String, dynamic>{},
            'required': <String>[],
          },
        },
      },
    ];

    List<Map<String, dynamic>> sentManifests() => sentFrames
        .map((frame) => jsonDecode(frame) as Map<String, dynamic>)
        .where((json) => json['type'] == 'tool_manifest')
        .toList();

    test('sends tool_manifest verbatim right after auth_success', () async {
      final manifestClient = GatewayClient(
        socketFactory: mockSocketFactory,
        toolManifestProvider: () => fixtureTools,
        clientId: 'pixel-8-indra',
        options: const GatewayClientOptions(
          heartbeatInterval: Duration(milliseconds: 50),
          heartbeatTimeout: Duration(milliseconds: 100),
          authTimeout: Duration(milliseconds: 100),
          connectTimeout: Duration(milliseconds: 100),
          initialReconnectDelay: Duration(milliseconds: 20),
          maxReconnectDelay: Duration(milliseconds: 50),
          reconnectBackoffFactor: 1.5,
        ),
      );
      addTearDown(manifestClient.dispose);

      await manifestClient.connect('ws://localhost:18789/device/ws', token: 'token123');

      // The auth frame is the only frame before auth_success.
      final authJson = jsonDecode(sentFrames.single) as Map<String, dynamic>;
      expect(authJson['type'], 'auth');
      expect(authJson['client_id'], 'pixel-8-indra');

      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      expect(manifestClient.state, GatewayConnectionState.connected);

      final manifests = sentManifests();
      expect(manifests.length, 1);

      final manifest = manifests.single;
      expect(manifest['type'], 'tool_manifest');
      expect(manifest['version'], 'v1');
      expect(manifest['device_id'], 'pixel-8-indra');
      expect(manifest['tools'], fixtureTools);
      // Nested function.parameters map survives verbatim.
      final tools = manifest['tools'] as List<dynamic>;
      final fn = (tools.first as Map<String, dynamic>)['function'] as Map<String, dynamic>;
      expect(fn['parameters'], fixtureTools.first['function']!['parameters']);
    });

    test('re-sends tool_manifest after auto-reconnect and second auth_success', () async {
      final manifestClient = GatewayClient(
        socketFactory: mockSocketFactory,
        toolManifestProvider: () => fixtureTools,
        clientId: 'pixel-8-indra',
        options: const GatewayClientOptions(
          heartbeatInterval: Duration(milliseconds: 50),
          heartbeatTimeout: Duration(milliseconds: 100),
          authTimeout: Duration(milliseconds: 100),
          connectTimeout: Duration(milliseconds: 100),
          initialReconnectDelay: Duration(milliseconds: 20),
          maxReconnectDelay: Duration(milliseconds: 50),
          reconnectBackoffFactor: 1.5,
        ),
      );
      addTearDown(manifestClient.dispose);

      await manifestClient.connect('ws://localhost:18789/device/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      expect(manifestClient.state, GatewayConnectionState.connected);
      expect(sentManifests().length, 1);

      final stateHistory = <GatewayConnectionState>[];
      final sub = manifestClient.stateStream.listen(stateHistory.add);

      // Second socket for the reconnected transport.
      final secondStreamController = StreamController<dynamic>.broadcast();
      final secondMockSocket = MockGatewaySocket();
      when(() => secondMockSocket.stream).thenAnswer((_) => secondStreamController.stream);
      when(() => secondMockSocket.send(any())).thenAnswer((invocation) {
        final frame = invocation.positionalArguments[0] as String;
        sentFrames.add(frame);
      });
      when(() => secondMockSocket.close(any(), any())).thenAnswer((_) async {
        if (!secondStreamController.isClosed) {
          await secondStreamController.close();
        }
      });

      when(() => mockSocketFactory.connect(any(), headers: any(named: 'headers'), timeout: any(named: 'timeout'), pingInterval: any(named: 'pingInterval')))
          .thenAnswer((_) async => secondMockSocket);

      // Unexpected socket drop -> auto-reconnect.
      await socketStreamController.close();
      await Future<void>.delayed(const Duration(milliseconds: 60));

      verify(() => mockSocketFactory.connect(any(), headers: any(named: 'headers'), timeout: any(named: 'timeout'), pingInterval: any(named: 'pingInterval'))).called(2);

      secondStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      expect(manifestClient.state, GatewayConnectionState.connected);
      expect(stateHistory.contains(GatewayConnectionState.reconnecting), isTrue);
      expect(sentManifests().length, 2);

      await sub.cancel();

      if (!secondStreamController.isClosed) {
        await secondStreamController.close();
      }
    });

    test('sends no tool_manifest when no provider is injected', () async {
      await client.connect('ws://localhost:18789/device/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      expect(client.state, GatewayConnectionState.connected);
      expect(sentManifests(), isEmpty);
    });

    test('a throwing manifest provider does not abort the handshake', () async {
      final manifestClient = GatewayClient(
        socketFactory: mockSocketFactory,
        toolManifestProvider: () => throw StateError('registry exploded'),
        options: const GatewayClientOptions(
          heartbeatInterval: Duration(milliseconds: 50),
          heartbeatTimeout: Duration(milliseconds: 100),
          authTimeout: Duration(milliseconds: 100),
          connectTimeout: Duration(milliseconds: 100),
          initialReconnectDelay: Duration(milliseconds: 20),
          maxReconnectDelay: Duration(milliseconds: 50),
          reconnectBackoffFactor: 1.5,
        ),
      );
      addTearDown(manifestClient.dispose);

      final errors = <Object>[];
      final sub = manifestClient.messageStream.listen(
        (_) {},
        onError: errors.add,
      );

      await manifestClient.connect('ws://localhost:18789/device/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();

      expect(manifestClient.state, GatewayConnectionState.connected);
      expect(sentManifests(), isEmpty);
      expect(errors, isEmpty);

      await sub.cancel();
    });
  });

  group('GatewayClient - Close Diagnostics', () {
    test('logs remote_closed with socket close code when stream ends', () async {
      when(() => mockSocket.closeCode).thenAnswer((_) => 1006);
      when(() => mockSocket.closeReason).thenAnswer((_) => 'gone silent');

      final quietClient = GatewayClient(
        socketFactory: mockSocketFactory,
        options: const GatewayClientOptions(autoReconnect: false),
      );
      addTearDown(quietClient.dispose);

      await quietClient.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();
      expect(quietClient.state, GatewayConnectionState.connected);

      final lines = await captureDebugPrint(() async {
        await socketStreamController.close();
        await pumpEventQueue();
      });

      expect(
        lines.any((line) => line.contains('cause=remote_closed code=1006')),
        isTrue,
      );
      expect(
        lines.any((line) => line.contains('reason=gone silent')),
        isTrue,
      );
    });

    test('logs app_watchdog when heartbeat pong never arrives', () async {
      final fastClient = GatewayClient(
        socketFactory: mockSocketFactory,
        options: const GatewayClientOptions(
          heartbeatInterval: Duration(milliseconds: 30),
          heartbeatTimeout: Duration(milliseconds: 40),
          autoReconnect: false,
        ),
      );
      addTearDown(fastClient.dispose);

      await fastClient.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();
      expect(fastClient.state, GatewayConnectionState.connected);

      final lines = await captureDebugPrint(
        () => Future<void>.delayed(const Duration(milliseconds: 160)),
      );

      expect(lines.any((line) => line.contains('cause=app_watchdog')), isTrue);
    });

    test('logs manual_disconnect when disconnect() is called', () async {
      await client.connect('ws://localhost:18789/ws', token: 'token123');
      socketStreamController.add(jsonEncode({'type': 'auth_success'}));
      await pumpEventQueue();
      expect(client.state, GatewayConnectionState.connected);

      final lines = await captureDebugPrint(() => client.disconnect());

      expect(
        lines.any((line) => line.contains('cause=manual_disconnect')),
        isTrue,
      );
    });

    test('logs auth_timeout when auth_success never arrives', () async {
      final lines = await captureDebugPrint(() async {
        await client.connect('ws://localhost:18789/ws', token: 'token123');
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });

      expect(lines.any((line) => line.contains('cause=auth_timeout')), isTrue);
    });
  });
}
