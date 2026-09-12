import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_rpc_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockGatewayClient mockGatewayClient;
  late MockToolRegistry mockToolRegistry;
  late StreamController<GatewayToolCallRequestMessage> toolRequestController;
  late GatewayRpcCubit cubit;

  setUpAll(() {
    registerFallbackValue(
      const GatewayToolCallRequestMessage(id: 'fb', tool: 'fb'),
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
  });

  tearDown(() async {
    await cubit.close();
    await toolRequestController.close();
  });

  group('GatewayRpcCubit - Initialization & Lifecycle', () {
    test('initial state is GatewayRpcInitial and starts listening by default',
        () {
      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
        autoStart: true,
      );

      expect(cubit.state, isA<GatewayRpcInitial>());
      expect(cubit.isListening, isTrue);
    });

    test('does not start listening when autoStart is false', () {
      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
        autoStart: false,
      );

      expect(cubit.isListening, isFalse);
      cubit.startListening();
      expect(cubit.isListening, isTrue);
      cubit.stopListening();
      expect(cubit.isListening, isFalse);
    });
  });

  group('GatewayRpcCubit - Tier 1 & Tier 2 Tool Calls', () {
    test('processes Tier 1 tool call: emits Executing then Completed and responds',
        () async {
      final tool = RegisteredTool(
        name: 'device_status',
        description: 'Battery & network status',
        parameters: const {'type': 'object', 'properties': {}},
        securityTier: SecurityTier.tier1Auto,
        execute: (_) async =>
            const Right('{"batteryLevel": 90, "wifi": true}'),
      );

      when(() => mockToolRegistry.getTool('device_status')).thenReturn(tool);
      when(() => mockToolRegistry.executeTool('device_status', any()))
          .thenAnswer((_) async =>
              const Right('{"batteryLevel": 90, "wifi": true}'));

      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
      );

      const request = GatewayToolCallRequestMessage(
        id: 'call_t1',
        tool: 'device_status',
        arguments: {},
      );

      final expectedStates = [
        const GatewayRpcExecuting(
          callId: 'call_t1',
          tool: 'device_status',
          arguments: {},
        ),
        const GatewayRpcCompleted(
          callId: 'call_t1',
          tool: 'device_status',
          result: {'batteryLevel': 90, 'wifi': true},
          error: null,
        ),
      ];

      expectLater(cubit.stream, emitsInOrder(expectedStates));

      toolRequestController.add(request);
      await pumpEventQueue();

      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'call_t1',
            result: {'batteryLevel': 90, 'wifi': true},
            error: null,
          )).called(1);
    });

    test('processes unknown tool call: emits Completed with error', () async {
      when(() => mockToolRegistry.getTool('invalid_tool')).thenReturn(null);

      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
      );

      const request = GatewayToolCallRequestMessage(
        id: 'call_unk',
        tool: 'invalid_tool',
        arguments: {},
      );

      final expectedStates = [
        const GatewayRpcExecuting(
          callId: 'call_unk',
          tool: 'invalid_tool',
          arguments: {},
        ),
        const GatewayRpcCompleted(
          callId: 'call_unk',
          tool: 'invalid_tool',
          result: null,
          error: 'Tool not found: invalid_tool',
        ),
      ];

      expectLater(cubit.stream, emitsInOrder(expectedStates));

      toolRequestController.add(request);
      await pumpEventQueue();

      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'call_unk',
            result: null,
            error: 'Tool not found: invalid_tool',
          )).called(1);
    });

    test('processes failed tool execution: emits Completed with failure message',
        () async {
      final tool = RegisteredTool(
        name: 'get_location',
        description: 'Get GPS location',
        parameters: const {'type': 'object', 'properties': {}},
        securityTier: SecurityTier.tier2Permission,
        execute: (_) async =>
            const Left(PermissionFailure('GPS permission denied by user')),
      );

      when(() => mockToolRegistry.getTool('get_location')).thenReturn(tool);
      when(() => mockToolRegistry.executeTool('get_location', any()))
          .thenAnswer((_) async =>
              const Left(PermissionFailure('GPS permission denied by user')));

      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
      );

      const request = GatewayToolCallRequestMessage(
        id: 'call_loc',
        tool: 'get_location',
        arguments: {},
      );

      final expectedStates = [
        const GatewayRpcExecuting(
          callId: 'call_loc',
          tool: 'get_location',
          arguments: {},
        ),
        const GatewayRpcCompleted(
          callId: 'call_loc',
          tool: 'get_location',
          result: null,
          error: 'GPS permission denied by user',
        ),
      ];

      expectLater(cubit.stream, emitsInOrder(expectedStates));

      toolRequestController.add(request);
      await pumpEventQueue();

      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'call_loc',
            result: null,
            error: 'GPS permission denied by user',
          )).called(1);
    });
  });

  group('GatewayRpcCubit - Tier 3 HITL Flow', () {
    test(
        'Tier 3 tool emits WaitingApproval, and approving executes tool and sends response',
        () async {
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
            const Right('Calendar event created with id: evt_123'),
      );

      when(() => mockToolRegistry.getTool('calendar_create_event'))
          .thenReturn(tool);
      when(() => mockToolRegistry.executeTool('calendar_create_event', any()))
          .thenAnswer((_) async =>
              const Right('Calendar event created with id: evt_123'));

      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
      );

      const request = GatewayToolCallRequestMessage(
        id: 'call_t3',
        tool: 'calendar_create_event',
        arguments: {'title': 'Quarterly Review'},
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      expect(cubit.state, isA<GatewayRpcWaitingApproval>());
      final waiting = cubit.state as GatewayRpcWaitingApproval;
      expect(waiting.request.id, 'call_t3');
      expect(waiting.request.name, 'calendar_create_event');
      expect(waiting.request.parameters['title'], 'Quarterly Review');
      expect(cubit.pendingApproval, equals(waiting.request));

      await cubit.approveAction('call_t3');
      await pumpEventQueue();

      expect(cubit.state, isA<GatewayRpcCompleted>());
      final completed = cubit.state as GatewayRpcCompleted;
      expect(completed.callId, 'call_t3');
      expect(completed.tool, 'calendar_create_event');
      expect(completed.result, {
        'output': 'Calendar event created with id: evt_123',
        'result': 'Calendar event created with id: evt_123',
      });
      expect(completed.error, isNull);
      expect(cubit.pendingApproval, isNull);

      verify(() => mockToolRegistry.executeTool(
            'calendar_create_event',
            {'title': 'Quarterly Review'},
          )).called(1);

      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'call_t3',
            result: {
              'output': 'Calendar event created with id: evt_123',
              'result': 'Calendar event created with id: evt_123',
            },
            error: null,
          )).called(1);
    });

    test('Tier 3 tool emits WaitingApproval, and rejecting sends rejection error',
        () async {
      final tool = RegisteredTool(
        name: 'schedule_reminder',
        description: 'Schedule reminder',
        parameters: const {'type': 'object', 'properties': {}},
        securityTier: SecurityTier.tier3Hitl,
        execute: (_) async => const Right('Reminder scheduled'),
      );

      when(() => mockToolRegistry.getTool('schedule_reminder')).thenReturn(tool);

      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
      );

      const request = GatewayToolCallRequestMessage(
        id: 'call_reject',
        tool: 'schedule_reminder',
        arguments: {'title': 'Call dentist'},
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      expect(cubit.state, isA<GatewayRpcWaitingApproval>());

      await cubit.rejectAction('call_reject');
      await pumpEventQueue();

      expect(cubit.state, isA<GatewayRpcCompleted>());
      final completed = cubit.state as GatewayRpcCompleted;
      expect(completed.callId, 'call_reject');
      expect(completed.tool, 'schedule_reminder');
      expect(completed.result, isNull);
      expect(completed.error, 'Action schedule_reminder was rejected by user.');

      verifyNever(() => mockToolRegistry.executeTool(any(), any()));
      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'call_reject',
            result: null,
            error: 'Action schedule_reminder was rejected by user.',
          )).called(1);
    });

    test(
        'closing cubit while Tier 3 approval is pending completes safely without throwing',
        () async {
      final tool = RegisteredTool(
        name: 'schedule_reminder',
        description: 'Schedule reminder',
        parameters: const {'type': 'object', 'properties': {}},
        securityTier: SecurityTier.tier3Hitl,
        execute: (_) async => const Right('Reminder scheduled'),
      );

      when(() => mockToolRegistry.getTool('schedule_reminder')).thenReturn(tool);

      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
      );

      const request = GatewayToolCallRequestMessage(
        id: 'call_pending_close',
        tool: 'schedule_reminder',
        arguments: {'title': 'Dentist appointment'},
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      expect(cubit.state, isA<GatewayRpcWaitingApproval>());

      await expectLater(cubit.close(), completes);
      await pumpEventQueue();

      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'call_pending_close',
            result: null,
            error: 'Action schedule_reminder was rejected by user.',
          )).called(1);
    });
  });
}
