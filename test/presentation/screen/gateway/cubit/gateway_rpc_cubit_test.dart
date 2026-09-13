import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/models/chat/tool_call_request.dart';
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
  late StreamController<GatewayElicitationRequestMessage>
      elicitationController;
  late GatewayRpcCubit cubit;

  setUpAll(() {
    registerFallbackValue(
      const GatewayToolCallRequestMessage(id: 'fb', tool: 'fb'),
    );
    registerFallbackValue(
      (ToolCallRequest request) async => true,
    );
  });

  setUp(() {
    mockGatewayClient = MockGatewayClient();
    mockToolRegistry = MockToolRegistry();
    toolRequestController =
        StreamController<GatewayToolCallRequestMessage>.broadcast();
    elicitationController =
        StreamController<GatewayElicitationRequestMessage>.broadcast();

    when(() => mockGatewayClient.toolCallRequestStream)
        .thenAnswer((_) => toolRequestController.stream);
    when(() => mockGatewayClient.elicitationRequestStream)
        .thenAnswer((_) => elicitationController.stream);

    when(() => mockGatewayClient.sendToolCallResponse(
          callId: any(named: 'callId'),
          result: any(named: 'result'),
          error: any(named: 'error'),
        )).thenReturn(null);
    when(() => mockGatewayClient.sendElicitationResponse(
          requestId: any(named: 'requestId'),
          approved: any(named: 'approved'),
          biometricVerified: any(named: 'biometricVerified'),
        )).thenReturn(null);
  });

  tearDown(() async {
    await cubit.close();
    await toolRequestController.close();
    await elicitationController.close();
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

  group('GatewayRpcCubit - Connection State Reconciliation', () {
    test(
        'syncWithConnectionState keeps listening for connected/connecting/'
        'reconnecting and startListening stays idempotent', () {
      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
        autoStart: false,
      );

      for (final state in [
        GatewayConnectionState.connecting,
        GatewayConnectionState.connected,
        GatewayConnectionState.reconnecting,
      ]) {
        cubit.syncWithConnectionState(state);
        expect(cubit.isListening, isTrue, reason: 'expected listening: $state');
      }

      // Idempotent: a single stream subscription across all live states.
      verify(() => mockGatewayClient.toolCallRequestStream).called(1);
    });

    test('syncWithConnectionState stops listening when disconnected', () {
      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
      );

      expect(cubit.isListening, isTrue);

      cubit.syncWithConnectionState(GatewayConnectionState.disconnected);

      expect(cubit.isListening, isFalse);
    });

    test(
        'request delivered while reconnecting is executed once and gets a '
        'single response (drop-free, no double execution)', () async {
      final tool = RegisteredTool(
        name: 'device_status',
        description: 'Battery & network status',
        parameters: const {'type': 'object', 'properties': {}},
        securityTier: SecurityTier.tier1Auto,
        execute: (_) async => const Right('{"batteryLevel": 42}'),
      );

      when(() => mockToolRegistry.getTool('device_status')).thenReturn(tool);
      when(() => mockToolRegistry.executeTool('device_status', any()))
          .thenAnswer((_) async => const Right('{"batteryLevel": 42}'));

      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
      );

      cubit.syncWithConnectionState(GatewayConnectionState.reconnecting);
      expect(cubit.isListening, isTrue);

      const request = GatewayToolCallRequestMessage(
        id: 'call_racing_reconnect',
        tool: 'device_status',
        arguments: {},
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      verify(() => mockGatewayClient.sendToolCallResponse(
            callId: 'call_racing_reconnect',
            result: {'batteryLevel': 42},
            error: null,
          )).called(1);
    });

    test(
        'never starts the injected receiver and keeps routing via '
        'handleRequest (single consumer regression guard)', () async {
      final mockReceiver = MockGatewayDeviceRpcReceiver();

      when(() => mockReceiver.handleRequest(
            any(),
            onApprovalRequired: any(named: 'onApprovalRequired'),
          )).thenAnswer(
        (_) async => const GatewayToolCallResponseMessage(
          id: 'call_single_consumer',
          result: {'ok': true},
          error: null,
        ),
      );

      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
        rpcReceiver: mockReceiver,
      );

      const request = GatewayToolCallRequestMessage(
        id: 'call_single_consumer',
        tool: 'device_status',
        arguments: {},
      );

      toolRequestController.add(request);
      await pumpEventQueue();

      verify(() => mockReceiver.handleRequest(
            any(),
            onApprovalRequired: any(named: 'onApprovalRequired'),
          )).called(1);
      verifyNever(() => mockReceiver.startListening());
      // The receiver owns the response frame; a second send here would mean a
      // duplicated subscription / double execution.
      verifyNever(() => mockGatewayClient.sendToolCallResponse(
            callId: any(named: 'callId'),
            result: any(named: 'result'),
            error: any(named: 'error'),
          ));
    });
  });

  group('Manifest / route name parity', () {
    late ToolRegistry realRegistry;
    late MockClipboardService mockClipboardService;
    late MockLocationService mockLocationService;
    late MockDeviceContextService mockDeviceContextService;

    setUp(() {
      mockClipboardService = MockClipboardService();
      mockLocationService = MockLocationService();
      mockDeviceContextService = MockDeviceContextService();

      when(() => mockClipboardService.clipboardRead())
          .thenAnswer((_) async => const Right('clip'));
      when(() => mockClipboardService.clipboardWrite(any()))
          .thenAnswer((_) async => const Right('ok'));
      when(() => mockLocationService.getLocationFormattedJson(
            accuracy: any(named: 'accuracy'),
          )).thenAnswer((_) async => const Right('{"latitude": 1.0}'));
      when(() => mockLocationService.checkPermission())
          .thenAnswer((_) async => true);
      when(() => mockDeviceContextService.deviceStatusFormattedJson())
          .thenAnswer((_) async => const Right('{"batteryLevel": 100}'));
      when(() => mockDeviceContextService.systemInfoFormattedJson())
          .thenAnswer((_) async => const Right('{"model": "test"}'));

      realRegistry = ToolRegistry(
        clipboardService: mockClipboardService,
        locationService: mockLocationService,
        deviceContextService: mockDeviceContextService,
      );
    });

    Set<String> advertisedNames() => realRegistry
        .getOpenAiToolDefinitions()
        .map((definition) =>
            (definition['function'] as Map<String, dynamic>)['name'] as String)
        .toSet();

    test('advertises registry names verbatim with no prefix logic', () {
      final names = advertisedNames();

      expect(names, isNotEmpty);

      // A `device_`-prefixed name is only advertised if the registry literally
      // registered it that way: the app never prepends a prefix.
      for (final name in names) {
        if (name.startsWith('device_')) {
          expect(realRegistry.hasTool(name), isTrue);
        }
      }

      final registryNames = realRegistry.tools.map((tool) => tool.name).toSet();
      expect(names, equals(registryNames));
    });

    test('every advertised name resolves through the cubit without not-found',
        () async {
      final names = advertisedNames();
      expect(names, isNotEmpty);

      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: realRegistry,
      );

      // Auto-approve any Tier 3 HITL gate so every advertised name reaches the
      // registry and produces a response frame.
      final approvalSub = cubit.stream.listen((state) {
        if (state is GatewayRpcWaitingApproval) {
          cubit.approveAction(state.request.id);
        }
      });

      for (final name in names) {
        toolRequestController.add(
          GatewayToolCallRequestMessage(id: 'parity_$name', tool: name),
        );
        await pumpEventQueue();

        final captured =
            verify(() => mockGatewayClient.sendToolCallResponse(
                  callId: 'parity_$name',
                  result: any(named: 'result'),
                  error: captureAny(named: 'error'),
                )).captured;

        expect(captured, hasLength(1));
        expect(
          captured.single,
          isNot('Tool not found: $name'),
          reason: 'manifest name "$name" must resolve to a registered tool',
        );
      }

      await approvalSub.cancel();
    });
  });

  group('GatewayRpcCubit - Remote HITL Elicitation', () {
    void createCubit({Duration? timeout}) {
      cubit = GatewayRpcCubit(
        gatewayClient: mockGatewayClient,
        toolRegistry: mockToolRegistry,
        autoStart: true,
        elicitationTimeout: timeout ?? const Duration(seconds: 120),
      );
    }

    void addElicitation(String id, {String risk = 'high'}) {
      elicitationController.add(GatewayElicitationRequestMessage(
        requestId: id,
        title: 'Fund transfer',
        description: 'Send 500 USDT to 0xdead',
        riskLevel: risk,
        fields: const [
          {'name': 'amount', 'value': '500'},
        ],
      ));
    }

    test('incoming elicitation_request emits GatewayRpcElicitationPending',
        () async {
      createCubit();

      addElicitation('elicit-1', risk: 'medium');
      await pumpEventQueue();

      final state = cubit.state;
      expect(state, isA<GatewayRpcElicitationPending>());
      final pending = state as GatewayRpcElicitationPending;
      expect(pending.requestId, 'elicit-1');
      expect(pending.title, 'Fund transfer');
      expect(pending.description, 'Send 500 USDT to 0xdead');
      expect(pending.riskLevel, 'medium');
      expect(pending.expiresAfter, const Duration(seconds: 120));
    });

    test('approveElicitation dispatches approved frame with biometric flag',
        () async {
      createCubit();
      addElicitation('elicit-2');
      await pumpEventQueue();

      await cubit.approveElicitation('elicit-2', biometricVerified: true);

      verify(() => mockGatewayClient.sendElicitationResponse(
            requestId: 'elicit-2',
            approved: true,
            biometricVerified: true,
          )).called(1);
      final state = cubit.state;
      expect(state, isA<GatewayRpcElicitationResolved>());
      expect((state as GatewayRpcElicitationResolved).approved, isTrue);
    });

    test('rejectElicitation dispatches rejected frame', () async {
      createCubit();
      addElicitation('elicit-3');
      await pumpEventQueue();

      await cubit.rejectElicitation('elicit-3');

      verify(() => mockGatewayClient.sendElicitationResponse(
            requestId: 'elicit-3',
            approved: false,
            biometricVerified: false,
          )).called(1);
      expect(cubit.state, isA<GatewayRpcElicitationResolved>());
    });

    test('resolving twice dispatches only one frame', () async {
      createCubit();
      addElicitation('elicit-dup');
      await pumpEventQueue();

      await cubit.approveElicitation('elicit-dup');
      await cubit.rejectElicitation('elicit-dup');

      verify(() => mockGatewayClient.sendElicitationResponse(
            requestId: 'elicit-dup',
            approved: any(named: 'approved'),
            biometricVerified: any(named: 'biometricVerified'),
          )).called(1);
    });

    test('timeout expiry auto-rejects and dispatches response frame',
        () async {
      createCubit(timeout: const Duration(milliseconds: 40));
      addElicitation('elicit-to');
      await pumpEventQueue();
      expect(cubit.state, isA<GatewayRpcElicitationPending>());

      await Future<void>.delayed(const Duration(milliseconds: 120));

      verify(() => mockGatewayClient.sendElicitationResponse(
            requestId: 'elicit-to',
            approved: false,
            biometricVerified: false,
          )).called(1);
      final state = cubit.state;
      expect(state, isA<GatewayRpcElicitationResolved>());
      expect((state as GatewayRpcElicitationResolved).approved, isFalse);
    });

    test('close resolves pending elicitations as rejected without frames',
        () async {
      createCubit();
      addElicitation('elicit-close');
      await pumpEventQueue();

      await cubit.close();

      verifyNever(() => mockGatewayClient.sendElicitationResponse(
            requestId: any(named: 'requestId'),
            approved: any(named: 'approved'),
            biometricVerified: any(named: 'biometricVerified'),
          ));
      expect(cubit.isClosed, isTrue);
    });

    test('a dead socket never throws while dispatching a decision', () async {
      createCubit();
      when(() => mockGatewayClient.sendElicitationResponse(
            requestId: any(named: 'requestId'),
            approved: any(named: 'approved'),
            biometricVerified: any(named: 'biometricVerified'),
          )).thenThrow(StateError('socket closed'));
      addElicitation('elicit-dead');
      await pumpEventQueue();

      await cubit.rejectElicitation('elicit-dead');

      expect(cubit.state, isA<GatewayRpcElicitationResolved>());
    });

    test(
        'disconnect rejects pending elicitations locally and ATTEMPTS a '
        'rejection frame (delivery after socket teardown is not guaranteed)',
        () async {
      createCubit();
      addElicitation('elicit-disc');
      await pumpEventQueue();

      cubit.syncWithConnectionState(GatewayConnectionState.disconnected);
      await pumpEventQueue();

      // Proves the local rejection is dispatched and a frame is attempted on
      // the client. Whether the bytes reach the server after teardown is the
      // transport's problem: the server falls back to its own timeout.
      verify(() => mockGatewayClient.sendElicitationResponse(
            requestId: 'elicit-disc',
            approved: false,
            biometricVerified: false,
          )).called(1);
      expect(cubit.state, isA<GatewayRpcElicitationResolved>());
      expect(cubit.isListening, isFalse);
    });

    test('duplicate request_id rejects the old request exactly once and keeps '
        'the new one pending', () async {
      createCubit();

      addElicitation('elicit-dup');
      await pumpEventQueue();
      addElicitation('elicit-dup');
      await pumpEventQueue();

      verify(() => mockGatewayClient.sendElicitationResponse(
            requestId: 'elicit-dup',
            approved: false,
            biometricVerified: false,
          )).called(1);
      expect(cubit.state, isA<GatewayRpcElicitationPending>());
      expect((cubit.state as GatewayRpcElicitationPending).requestId,
          'elicit-dup');

      // The second registration owns the slot: resolving it sends an approval.
      await cubit.approveElicitation('elicit-dup');
      verify(() => mockGatewayClient.sendElicitationResponse(
            requestId: 'elicit-dup',
            approved: true,
            biometricVerified: false,
          )).called(1);
    });

    test('elicitation frame with blank request_id is ignored without emitting',
        () async {
      createCubit();
      final states = <GatewayRpcState>[];
      final sub = cubit.stream.listen(states.add);

      elicitationController.add(const GatewayElicitationRequestMessage(
        requestId: '   ',
        title: 'Unaddressable',
        description: 'No id to respond to',
        riskLevel: 'high',
      ));
      await pumpEventQueue();

      expect(states, isEmpty);
      expect(cubit.state, isA<GatewayRpcInitial>());
      verifyNever(() => mockGatewayClient.sendElicitationResponse(
            requestId: any(named: 'requestId'),
            approved: any(named: 'approved'),
            biometricVerified: any(named: 'biometricVerified'),
          ));
      await sub.cancel();
    });

    test('pending state carries request fields for the approval sheet',
        () async {
      createCubit();
      addElicitation('elicit-fields');
      await pumpEventQueue();

      final pending = cubit.state as GatewayRpcElicitationPending;
      expect(pending.fields, const [
        {'name': 'amount', 'value': '500'},
      ]);
    });
  });
}
