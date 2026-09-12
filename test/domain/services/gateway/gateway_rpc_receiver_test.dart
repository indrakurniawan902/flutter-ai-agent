import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/models/chat/tool_call_request.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';

class MockGatewayClient extends Mock implements GatewayClientBase {}

class MockToolRegistry extends Mock implements ToolRegistry {}

void main() {
  late MockGatewayClient mockGatewayClient;
  late MockToolRegistry mockToolRegistry;
  late StreamController<GatewayToolCallRequestMessage> toolRequestController;
  late GatewayDeviceRpcReceiver receiver;

  setUpAll(() {
    registerFallbackValue(
      const GatewayToolCallRequestMessage(id: 'fallback', tool: 'fallback'),
    );
  });

  setUp(() {
    mockGatewayClient = MockGatewayClient();
    mockToolRegistry = MockToolRegistry();
    toolRequestController =
        StreamController<GatewayToolCallRequestMessage>.broadcast();

    when(() => mockGatewayClient.toolCallRequestStream)
        .thenAnswer((_) => toolRequestController.stream);

    when(() => mockGatewayClient.sendToolCallResponse(
          callId: any(named: 'callId'),
          result: any(named: 'result'),
          error: any(named: 'error'),
        )).thenReturn(null);

    receiver = GatewayDeviceRpcReceiver(
      gatewayClient: mockGatewayClient,
      toolRegistry: mockToolRegistry,
    );
  });

  tearDown(() {
    receiver.dispose();
    toolRequestController.close();
  });

  group('GatewayDeviceRpcReceiver - Lifecycle', () {
    test('isListening reflects listening state', () {
      expect(receiver.isListening, isFalse);
      receiver.startListening();
      expect(receiver.isListening, isTrue);
      receiver.stopListening();
      expect(receiver.isListening, isFalse);
    });

    test('startListening is idempotent', () {
      receiver.startListening();
      receiver.startListening();
      expect(receiver.isListening, isTrue);
    });
  });

  group('GatewayDeviceRpcReceiver - Tool Dispatching', () {
    test('executes Tier 1 tool automatically and sends parsed JSON result',
        () async {
      final tool = RegisteredTool(
        name: 'device_status',
        description: 'Returns battery and wifi status',
        parameters: const {'type': 'object', 'properties': {}},
        securityTier: SecurityTier.tier1Auto,
        execute: (_) async => const Right('{"batteryLevel": 85, "wifi": true}'),
      );

      when(() => mockToolRegistry.getTool('device_status')).thenReturn(tool);
      when(() => mockToolRegistry.executeTool('device_status', any()))
          .thenAnswer((_) async =>
              const Right('{"batteryLevel": 85, "wifi": true}'));

      receiver.startListening();

      const request = GatewayToolCallRequestMessage(
        id: 'req_1',
        tool: 'device_status',
        arguments: {},
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      verify(() => mockToolRegistry.executeTool('device_status', {})).called(1);
      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'req_1',
            result: {'batteryLevel': 85, 'wifi': true},
            error: null,
          )).called(1);
    });

    test('executes Tier 1 tool returning plain text and wraps in result map',
        () async {
      final tool = RegisteredTool(
        name: 'clipboard_read',
        description: 'Read clipboard',
        parameters: const {'type': 'object', 'properties': {}},
        securityTier: SecurityTier.tier1Auto,
        execute: (_) async => const Right('Hello world text'),
      );

      when(() => mockToolRegistry.getTool('clipboard_read')).thenReturn(tool);
      when(() => mockToolRegistry.executeTool('clipboard_read', any()))
          .thenAnswer((_) async => const Right('Hello world text'));

      receiver.startListening();

      const request = GatewayToolCallRequestMessage(
        id: 'req_clip',
        tool: 'clipboard_read',
        arguments: {},
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      verify(() => mockToolRegistry.executeTool('clipboard_read', {})).called(1);
      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'req_clip',
            result: {'output': 'Hello world text', 'result': 'Hello world text'},
            error: null,
          )).called(1);
    });

    test('returns error when tool is not registered', () async {
      when(() => mockToolRegistry.getTool('unknown_tool')).thenReturn(null);

      receiver.startListening();

      const request = GatewayToolCallRequestMessage(
        id: 'req_unknown',
        tool: 'unknown_tool',
        arguments: {},
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      verifyNever(() => mockToolRegistry.executeTool(any(), any()));
      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'req_unknown',
            result: null,
            error: 'Tool not found: unknown_tool',
          )).called(1);
    });

    test(
        'handleRequest returns a structured not-found error and does not throw',
        () async {
      when(() => mockToolRegistry.getTool('ghost_tool')).thenReturn(null);

      final response = await receiver.handleRequest(
        const GatewayToolCallRequestMessage(
          id: 'req_ghost',
          tool: 'ghost_tool',
        ),
      );

      expect(response.result, isNull);
      expect(response.error, isA<String>());
      expect(response.error, isNotEmpty);
      expect(response.error, contains('ghost_tool'));

      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'req_ghost',
            result: null,
            error: response.error,
          )).called(1);
    });

    test('returns error when tool execution fails with Failure', () async {
      final tool = RegisteredTool(
        name: 'get_location',
        description: 'Get location',
        parameters: const {'type': 'object', 'properties': {}},
        securityTier: SecurityTier.tier2Permission,
        execute: (_) async =>
            const Left(PermissionFailure('Location permission denied')),
      );

      when(() => mockToolRegistry.getTool('get_location')).thenReturn(tool);
      when(() => mockToolRegistry.executeTool('get_location', any()))
          .thenAnswer((_) async =>
              const Left(PermissionFailure('Location permission denied')));

      receiver.startListening();

      const request = GatewayToolCallRequestMessage(
        id: 'req_loc',
        tool: 'get_location',
        arguments: {'accuracy': 'high'},
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'req_loc',
            result: null,
            error: 'Location permission denied',
          )).called(1);
    });

    test('returns error when tool execution throws unexpected exception',
        () async {
      final tool = RegisteredTool(
        name: 'camera_take_photo',
        description: 'Take photo',
        parameters: const {'type': 'object', 'properties': {}},
        securityTier: SecurityTier.tier2Permission,
        execute: (_) async => throw Exception('Camera sensor hardware fault'),
      );

      when(() => mockToolRegistry.getTool('camera_take_photo')).thenReturn(tool);
      when(() => mockToolRegistry.executeTool('camera_take_photo', any()))
          .thenThrow(Exception('Camera sensor hardware fault'));

      receiver.startListening();

      const request = GatewayToolCallRequestMessage(
        id: 'req_cam',
        tool: 'camera_take_photo',
        arguments: {'source': 'camera'},
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'req_cam',
            result: null,
            error: any(
              named: 'error',
              that: contains('Camera sensor hardware fault'),
            ),
          )).called(1);
    });
  });

  group('GatewayDeviceRpcReceiver - Tier 3 HITL Gate', () {
    test('pauses and executes Tier 3 tool when user approves', () async {
      final tool = RegisteredTool(
        name: 'calendar_create_event',
        description: 'Create calendar event',
        parameters: const {
          'type': 'object',
          'properties': {
            'title': {'type': 'string'},
          },
        },
        securityTier: SecurityTier.tier3Hitl,
        execute: (_) async =>
            const Right('Calendar event created with id: evt_99'),
      );

      when(() => mockToolRegistry.getTool('calendar_create_event'))
          .thenReturn(tool);
      when(() => mockToolRegistry.executeTool('calendar_create_event', any()))
          .thenAnswer((_) async =>
              const Right('Calendar event created with id: evt_99'));

      final completer = Completer<bool>();
      ToolCallRequest? capturedRequest;

      final receiverWithHitl = GatewayDeviceRpcReceiver(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
        onApprovalRequired: (req) {
          capturedRequest = req;
          return completer.future;
        },
      );
      receiverWithHitl.startListening();

      const request = GatewayToolCallRequestMessage(
        id: 'req_cal',
        tool: 'calendar_create_event',
        arguments: {
          'title': 'Team Standup',
          'startTime': '2026-09-12T10:00:00Z',
        },
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      // Should have triggered approval handler and paused
      expect(capturedRequest, isNotNull);
      expect(capturedRequest!.id, 'req_cal');
      expect(capturedRequest!.name, 'calendar_create_event');
      expect(capturedRequest!.parameters['title'], 'Team Standup');
      verifyNever(() => mockToolRegistry.executeTool(any(), any()));

      // Now approve
      completer.complete(true);
      await pumpEventQueue();

      // Tool executes and response is sent
      verify(() => mockToolRegistry.executeTool('calendar_create_event', {
            'title': 'Team Standup',
            'startTime': '2026-09-12T10:00:00Z',
          })).called(1);

      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'req_cal',
            result: {
              'output': 'Calendar event created with id: evt_99',
              'result': 'Calendar event created with id: evt_99',
            },
            error: null,
          )).called(1);

      receiverWithHitl.dispose();
    });

    test('aborts and returns rejection error when user rejects Tier 3 tool',
        () async {
      final tool = RegisteredTool(
        name: 'schedule_reminder',
        description: 'Schedule reminder',
        parameters: const {'type': 'object', 'properties': {}},
        securityTier: SecurityTier.tier3Hitl,
        execute: (_) async => const Right('Scheduled'),
      );

      when(() => mockToolRegistry.getTool('schedule_reminder')).thenReturn(tool);

      final completer = Completer<bool>();

      final receiverWithHitl = GatewayDeviceRpcReceiver(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
        onApprovalRequired: (req) => completer.future,
      );
      receiverWithHitl.startListening();

      const request = GatewayToolCallRequestMessage(
        id: 'req_rem',
        tool: 'schedule_reminder',
        arguments: {'title': 'Buy coffee', 'delayMinutes': 10},
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      verifyNever(() => mockToolRegistry.executeTool(any(), any()));

      // User rejects
      completer.complete(false);
      await pumpEventQueue();

      // Never executes tool
      verifyNever(() => mockToolRegistry.executeTool(any(), any()));

      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'req_rem',
            result: null,
            error: 'Action schedule_reminder was rejected by user.',
          )).called(1);

      receiverWithHitl.dispose();
    });

    test('safely rejects Tier 3 tool when onApprovalRequired handler is null',
        () async {
      final tool = RegisteredTool(
        name: 'calendar_create_event',
        description: 'Create calendar event',
        parameters: const {'type': 'object', 'properties': {}},
        securityTier: SecurityTier.tier3Hitl,
        execute: (_) async => const Right('Created'),
      );

      when(() => mockToolRegistry.getTool('calendar_create_event'))
          .thenReturn(tool);

      receiver.startListening();

      const request = GatewayToolCallRequestMessage(
        id: 'req_cal_no_handler',
        tool: 'calendar_create_event',
        arguments: {},
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      verifyNever(() => mockToolRegistry.executeTool(any(), any()));
      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'req_cal_no_handler',
            result: null,
            error:
                'Action calendar_create_event requires user approval, but no approval handler was registered.',
          )).called(1);
    });
  });
}
