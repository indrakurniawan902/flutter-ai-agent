import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_mode.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_request.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_approval_sheet.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/elicitation_approval_sheet.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/header_console_bar.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_link_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_rpc_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/pairing/qr_scanner_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  late MockAgentCubit mockAgentCubit;
  late MockSettingsCubit mockSettingsCubit;
  late MockGatewayClient mockGatewayClient;
  late MockGatewayRpcCubit mockGatewayRpcCubit;
  late MockServerProfileCubit mockServerProfileCubit;

  late StreamController<AgentState> agentStateController;
  late StreamController<GatewayConnectionState> gatewayStateController;
  late StreamController<GatewayRpcState> gatewayRpcStateController;
  late StreamController<GatewayMessage> gatewayMessageController;
  late StreamController<GatewayTextDeltaMessage> gatewayTextDeltaController;
  late StreamController<ServerProfileState> serverProfileStateController;
  late StreamController<GatewayToolCallRequestMessage> toolRequestController;
  late StreamController<GatewayElicitationRequestMessage>
      elicitationRequestController;

  final sampleProfile = ServerProfile(
    id: 'prof-1',
    name: 'Home Gateway',
    gatewayUrl: 'https://gateway.example.com',
    token: 'test-token-123',
    isActive: true,
    lastConnected: DateTime(2026, 9, 11),
  );

  setUpAll(() {
    registerFallbackValue(sampleProfile);
    registerFallbackValue(const ChatMessage(role: 'user', content: 'fallback'));
    registerFallbackValue(PairingPayload(
      gatewayUrl: 'https://gateway.example.com',
      token: 'tok',
      profileName: 'Hermes Gateway',
      timestamp: DateTime(2026, 9, 11),
    ));
    registerFallbackValue(GatewayConnectionState.disconnected);
  });

  setUp(() async {
    await sl.reset();

    mockAgentCubit = MockAgentCubit();
    mockSettingsCubit = MockSettingsCubit();
    mockGatewayClient = MockGatewayClient();
    mockGatewayRpcCubit = MockGatewayRpcCubit();
    mockServerProfileCubit = MockServerProfileCubit();

    agentStateController = StreamController<AgentState>.broadcast();
    gatewayStateController =
        StreamController<GatewayConnectionState>.broadcast();
    gatewayRpcStateController = StreamController<GatewayRpcState>.broadcast();
    gatewayMessageController = StreamController<GatewayMessage>.broadcast();
    gatewayTextDeltaController =
        StreamController<GatewayTextDeltaMessage>.broadcast();
    serverProfileStateController =
        StreamController<ServerProfileState>.broadcast();
    toolRequestController =
        StreamController<GatewayToolCallRequestMessage>.broadcast();
    elicitationRequestController =
        StreamController<GatewayElicitationRequestMessage>.broadcast();

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.sessions).thenReturn(const []);
    when(() => mockAgentCubit.activeSessionId).thenReturn(null);
    when(() => mockAgentCubit.activeSessionTitle).thenReturn('New chat');
    when(() => mockAgentCubit.refreshSessions()).thenAnswer((_) async {});
    when(() => mockAgentCubit.newChat()).thenAnswer((_) async {});
    when(() => mockAgentCubit.switchSession(any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.renameSession(any(), any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.deleteSession(any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.messages).thenReturn([]);
    when(() => mockAgentCubit.stream)
        .thenAnswer((_) => agentStateController.stream);
    when(() => mockAgentCubit.switchProfile(any()))
        .thenAnswer((_) async {});
    when(() => mockAgentCubit.addMessage(any())).thenReturn(null);

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsLoaded(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o',
        temperature: 0.7,
      ),
    );
    when(() => mockSettingsCubit.stream)
        .thenAnswer((_) => const Stream.empty());

    when(() => mockGatewayClient.state)
        .thenReturn(GatewayConnectionState.disconnected);
    when(() => mockGatewayClient.stateStream)
        .thenAnswer((_) => gatewayStateController.stream);
    when(() => mockGatewayClient.messageStream)
        .thenAnswer((_) => gatewayMessageController.stream);
    when(() => mockGatewayClient.textDeltaStream)
        .thenAnswer((_) => gatewayTextDeltaController.stream);
    when(() => mockGatewayClient.connect(any(), token: any(named: 'token')))
        .thenAnswer((_) async {});
    when(() => mockGatewayClient.connectWithProfile(any()))
        .thenAnswer((_) async {});
    when(() => mockGatewayClient.disconnect(reason: any(named: 'reason')))
        .thenAnswer((_) async {});

    when(() => mockGatewayRpcCubit.state)
        .thenReturn(const GatewayRpcInitial());
    when(() => mockGatewayRpcCubit.stream)
        .thenAnswer((_) => gatewayRpcStateController.stream);
    when(() => mockGatewayRpcCubit.startListening()).thenReturn(null);
    when(() => mockGatewayRpcCubit.stopListening()).thenReturn(null);
    when(() => mockGatewayRpcCubit.syncWithConnectionState(any()))
        .thenReturn(null);

    when(() => mockServerProfileCubit.state).thenReturn(
      ServerProfileLoaded(profiles: [sampleProfile], activeProfile: sampleProfile),
    );
    when(() => mockServerProfileCubit.stream)
        .thenAnswer((_) => serverProfileStateController.stream);
    when(() => mockServerProfileCubit.addFromPairingPayload(any(),
            makeActive: any(named: 'makeActive')))
        .thenAnswer((_) async {});

    sl.registerFactory<AgentCubit>(() => mockAgentCubit);
    sl.registerFactory<SettingsCubit>(() => mockSettingsCubit);
    sl.registerLazySingleton<GatewayClientBase>(() => mockGatewayClient);
    sl.registerFactory<GatewayRpcCubit>(() => mockGatewayRpcCubit);
    sl.registerFactory<ServerProfileCubit>(() => mockServerProfileCubit);
  });

  tearDown(() async {
    await agentStateController.close();
    await gatewayStateController.close();
    await gatewayRpcStateController.close();
    await gatewayMessageController.close();
    await gatewayTextDeltaController.close();
    await serverProfileStateController.close();
    await toolRequestController.close();
    await elicitationRequestController.close();
    await sl.reset();
  });

  Widget createWidgetUnderTest({
    ChatMode initialMode = ChatMode.direct,
    GatewayRpcCubit? gatewayRpcCubit,
  }) {
    return MaterialApp(
      home: ChatScreen(
        initialMode: initialMode,
        gatewayClient: mockGatewayClient,
        gatewayRpcCubit: gatewayRpcCubit ?? mockGatewayRpcCubit,
        serverProfileCubit: mockServerProfileCubit,
      ),
    );
  }

  /// Real cubit wired to the mock client, so elicitation frames are produced
  /// and consumed through the genuine dispatch path (no self-stubbing).
  GatewayRpcCubit createRealRpcCubit() {
    when(() => mockGatewayClient.toolCallRequestStream)
        .thenAnswer((_) => toolRequestController.stream);
    when(() => mockGatewayClient.elicitationRequestStream)
        .thenAnswer((_) => elicitationRequestController.stream);
    when(() => mockGatewayClient.sendElicitationResponse(
          requestId: any(named: 'requestId'),
          approved: any(named: 'approved'),
          biometricVerified: any(named: 'biometricVerified'),
        )).thenReturn(null);
    final cubit = GatewayRpcCubit(
      gatewayClient: mockGatewayClient,
      toolRegistry: MockToolRegistry(),
      autoStart: false,
    );
    addTearDown(cubit.close);
    return cubit;
  }

  void addElicitationFrame(String id, {required String title}) {
    elicitationRequestController.add(GatewayElicitationRequestMessage(
      requestId: id,
      title: title,
      description: 'Remote HITL request $title',
      riskLevel: 'high',
    ));
  }

  Finder statusChipText(String label) => find.descendant(
        of: find.byKey(const Key('gateway_status_chip')),
        matching: find.text(label),
      );

  PulsingDot statusChipDot(WidgetTester tester) => tester.widget<PulsingDot>(
        find.descendant(
          of: find.byKey(const Key('gateway_status_chip')),
          matching: find.byType(PulsingDot),
        ),
      );

  group('ChatScreen Gateway - Connection Status Indicator', () {
    testWidgets('renders Standalone with Grey LED dot in Direct mode',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(initialMode: ChatMode.direct));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(statusChipText('Standalone'), findsOneWidget);

      expect(statusChipDot(tester).color, const Color(0xFF94A3B8));
    });

    testWidgets(
        'renders Connected with Green LED dot in Gateway mode when connected',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.connected);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(statusChipText('Connected'), findsOneWidget);

      expect(statusChipDot(tester).color, const Color(0xFF22C55E));
    });

    testWidgets(
        'renders Reconnecting with Amber LED dot in Gateway mode when reconnecting',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.reconnecting);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(statusChipText('Reconnecting'), findsOneWidget);

      expect(statusChipDot(tester).color, const Color(0xFFF59E0B));
    });

    testWidgets(
        'renders Connecting with Amber LED dot in Gateway mode when connecting',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.connecting);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(statusChipText('Connecting'), findsOneWidget);

      expect(statusChipDot(tester).color, const Color(0xFFF59E0B));
    });

    testWidgets(
        'renders Disconnected with Grey LED dot in Gateway mode when disconnected',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.disconnected);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('gateway_status_chip')), findsOneWidget);
      expect(statusChipText('Disconnected'), findsOneWidget);

      expect(statusChipDot(tester).color, const Color(0xFF94A3B8));
    });

    testWidgets('dynamically updates indicator on gateway stateStream transition',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.disconnected);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();
      expect(statusChipText('Disconnected'), findsOneWidget);

      gatewayStateController.add(GatewayConnectionState.connecting);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(statusChipText('Connecting'), findsOneWidget);

      gatewayStateController.add(GatewayConnectionState.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(statusChipText('Connected'), findsOneWidget);

      gatewayStateController.add(GatewayConnectionState.reconnecting);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(statusChipText('Reconnecting'), findsOneWidget);
    });

    testWidgets('tapping connection indicator displays connection details dialog',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.connected);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('gateway_status_chip')));
      await tester.pumpAndSettle();

      expect(find.text('Connection Status'), findsOneWidget);
      expect(find.textContaining('Connected'), findsWidgets);
      expect(find.textContaining('Home Gateway'), findsOneWidget);
    });
  });

  group('ChatScreen Gateway - Mode Switching', () {
    testWidgets(
        'toggling mode switches from Direct to Gateway and triggers connection',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.disconnected);

      await tester.pumpWidget(createWidgetUnderTest(initialMode: ChatMode.direct));
      await tester.pumpAndSettle();

      expect(find.text('Standalone'), findsOneWidget);
      expect(find.byKey(const Key('chat_mode_toggle')), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat_mode_toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Switched to Gateway Remote Node mode'), findsOneWidget);
      verify(() => mockGatewayClient.connectWithProfile(sampleProfile)).called(1);
    });

    testWidgets(
        'gateway connect is routed through a registered GatewayLinkCubit',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.disconnected);

      final backgroundFake = _RecordingBackgroundService();
      final linkCubit = GatewayLinkCubit(
        gatewayClient: mockGatewayClient,
        backgroundService: backgroundFake,
        autoStart: false,
      );
      addTearDown(linkCubit.close);
      sl.registerLazySingleton<GatewayLinkCubit>(() => linkCubit);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.direct));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_mode_toggle')));
      await tester.pumpAndSettle();

      // Connect went through the link cubit's startWithProfile, which
      // delegates to the client itself.
      verify(() => mockGatewayClient.connectWithProfile(sampleProfile))
          .called(1);

      // The link policy is observing: a connected event drives the
      // foreground service + wake lock through the background service.
      gatewayStateController.add(GatewayConnectionState.connected);
      await tester.pumpAndSettle();

      expect(backgroundFake.calls, contains('startService'));
      expect(backgroundFake.calls, contains('acquireWakeLock'));
    });

    testWidgets(
        'toggling mode switches from Gateway to Direct and disconnects gateway',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.connected);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      expect(find.text('Connected'), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat_mode_toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Switched to Direct LLM mode'), findsOneWidget);
      expect(find.text('Standalone'), findsOneWidget);
      verify(() => mockGatewayClient.disconnect(reason: any(named: 'reason')))
          .called(1);
    });

    testWidgets(
        'switching to Direct stops the RPC listener and switching back to '
        'Gateway starts it again', (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.disconnected);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.direct));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_mode_toggle')));
      await tester.pumpAndSettle();

      verify(() => mockGatewayRpcCubit.startListening()).called(1);
      expect(find.text('Switched to Gateway Remote Node mode'), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat_mode_toggle')));
      await tester.pumpAndSettle();

      verify(() => mockGatewayRpcCubit.stopListening()).called(1);
      // The mode indicator returns to Standalone (Direct LLM). The mode-switch
      // SnackBar text is asserted by the two tests above; asserting it again
      // here would race the still-visible first SnackBar.
      expect(find.text('Standalone'), findsOneWidget);
    });

    testWidgets(
        'Direct mode connection state transitions do not start RPC listening',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.disconnected);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.direct));
      await tester.pumpAndSettle();

      gatewayStateController.add(GatewayConnectionState.connecting);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      gatewayStateController.add(GatewayConnectionState.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      gatewayStateController.add(GatewayConnectionState.reconnecting);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      verifyNever(() => mockGatewayRpcCubit.startListening());
      verifyNever(() => mockGatewayRpcCubit.syncWithConnectionState(any()));
    });
  });

  group('ChatScreen Gateway - Quick QR Code Scanner', () {
    testWidgets('renders QR scan button in AppBar', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_qr_scan_button')), findsOneWidget);
    });

    testWidgets('tapping QR scan button navigates to QrScannerScreen',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_qr_scan_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(QrScannerScreen), findsOneWidget);
    });
  });

  group('ChatScreen Gateway - Chat & Remote Tool HITL Gate', () {
    testWidgets('submitting message in Gateway mode when connected sends chat frame',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.connected);
      when(() => mockGatewayClient.sendChatMessage(any())).thenReturn(null);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('chat_input_field')), 'Turn on flashlight');
      await tester.pump();

      await tester.tap(find.byKey(const Key('chat_send_button')));
      await tester.pump();

      verify(() => mockGatewayClient.sendChatMessage('Turn on flashlight'))
          .called(1);
      expect(find.text('Turn on flashlight'), findsNothing);
    });

    testWidgets(
        'submitting message in Gateway mode when disconnected shows warning SnackBar',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.disconnected);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('chat_input_field')), 'Hello');
      await tester.pump();

      await tester.tap(find.byKey(const Key('chat_send_button')));
      await tester.pump();

      expect(find.textContaining('Gateway not connected'), findsOneWidget);
      verifyNever(() => mockGatewayClient.sendChatMessage(any()));
    });

    testWidgets(
        'shows ActionApprovalSheet on GatewayRpcWaitingApproval and handles approval',
        (tester) async {
      when(() => mockGatewayRpcCubit.approveAction(any()))
          .thenAnswer((_) async {});

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      const request = ToolCallRequest(
        id: 'rpc_req_42',
        name: 'calendar_create_event',
        parameters: {'title': 'Meeting with Ops'},
      );

      gatewayRpcStateController.add(const GatewayRpcWaitingApproval(request));
      await tester.pumpAndSettle();

      expect(find.byType(ActionApprovalSheet), findsOneWidget);
      expect(find.text('calendar_create_event'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      verify(() => mockGatewayRpcCubit.approveAction('rpc_req_42')).called(1);
      expect(find.byType(ActionApprovalSheet), findsNothing);
    });

    testWidgets(
        'shows ActionApprovalSheet on GatewayRpcWaitingApproval and handles rejection',
        (tester) async {
      when(() => mockGatewayRpcCubit.rejectAction(any()))
          .thenAnswer((_) async {});

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      const request = ToolCallRequest(
        id: 'rpc_req_43',
        name: 'calendar_create_event',
        parameters: {'title': 'Delete Database'},
      );

      gatewayRpcStateController.add(const GatewayRpcWaitingApproval(request));
      await tester.pumpAndSettle();

      expect(find.byType(ActionApprovalSheet), findsOneWidget);

      await tester.tap(find.text('Reject'));
      await tester.pumpAndSettle();

      verify(() => mockGatewayRpcCubit.rejectAction('rpc_req_43')).called(1);
      expect(find.byType(ActionApprovalSheet), findsNothing);
    });

    testWidgets(
        'shows ElicitationApprovalSheet on GatewayRpcElicitationPending and '
        'tapping Reject dispatches a rejection response', (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.connected);
      final rpcCubit = createRealRpcCubit();

      await tester.pumpWidget(createWidgetUnderTest(
        initialMode: ChatMode.gateway,
        gatewayRpcCubit: rpcCubit,
      ));
      await tester.pumpAndSettle();

      addElicitationFrame('elicit_ui_1', title: 'Fund transfer');
      await tester.pumpAndSettle();

      expect(find.byType(ElicitationApprovalSheet), findsOneWidget);
      expect(find.text('HIGH RISK'), findsOneWidget);
      expect(find.text('Fund transfer'), findsOneWidget);

      await tester.tap(find.byKey(const Key('elicitation_reject_button')));
      await tester.pumpAndSettle();

      // Verified through the real cubit path: the tap must make the gateway
      // client emit a rejection frame for exactly this request id.
      verify(() => mockGatewayClient.sendElicitationResponse(
            requestId: 'elicit_ui_1',
            approved: false,
            biometricVerified: false,
          )).called(1);
      expect(find.byType(ElicitationApprovalSheet), findsNothing);
      expect(rpcCubit.state, isA<GatewayRpcElicitationResolved>());
    });

    testWidgets(
        'two concurrent elicitations: rejecting the topmost sheet pops that '
        'sheet and keeps the older one pending', (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.connected);
      final rpcCubit = createRealRpcCubit();

      await tester.pumpWidget(createWidgetUnderTest(
        initialMode: ChatMode.gateway,
        gatewayRpcCubit: rpcCubit,
      ));
      await tester.pumpAndSettle();

      addElicitationFrame('elicit_first', title: 'First request');
      await tester.pumpAndSettle();
      addElicitationFrame('elicit_second', title: 'Second request');
      await tester.pumpAndSettle();

      expect(find.byType(ElicitationApprovalSheet), findsNWidgets(2));

      await tester.tap(
          find.byKey(const Key('elicitation_reject_button')).last);
      await tester.pumpAndSettle();

      verify(() => mockGatewayClient.sendElicitationResponse(
            requestId: 'elicit_second',
            approved: false,
            biometricVerified: false,
          )).called(1);
      verifyNever(() => mockGatewayClient.sendElicitationResponse(
            requestId: 'elicit_first',
            approved: any(named: 'approved'),
            biometricVerified: any(named: 'biometricVerified'),
          ));

      // Topmost sheet gone, the older one still awaits a decision.
      expect(find.byType(ElicitationApprovalSheet), findsOneWidget);
      expect(find.text('First request'), findsOneWidget);
      expect(find.text('Second request'), findsNothing);

      await tester.tap(find.byKey(const Key('elicitation_reject_button')));
      await tester.pumpAndSettle();

      verify(() => mockGatewayClient.sendElicitationResponse(
            requestId: 'elicit_first',
            approved: false,
            biometricVerified: false,
          )).called(1);
      expect(find.byType(ElicitationApprovalSheet), findsNothing);
    });

    testWidgets(
        'leaving the chat screen rejects every still-open elicitation sheet',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.connected);
      final rpcCubit = createRealRpcCubit();

      await tester.pumpWidget(createWidgetUnderTest(
        initialMode: ChatMode.gateway,
        gatewayRpcCubit: rpcCubit,
      ));
      await tester.pumpAndSettle();

      addElicitationFrame('elicit_leave', title: 'Leaving demo');
      await tester.pumpAndSettle();
      expect(find.byType(ElicitationApprovalSheet), findsOneWidget);

      // Unmounting the screen must not leave the server hanging.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.pumpAndSettle();

      verify(() => mockGatewayClient.sendElicitationResponse(
            requestId: 'elicit_leave',
            approved: false,
            biometricVerified: false,
          )).called(1);
    });

    testWidgets(
        'elicitation sheet surfaces request fields and drops the raw id dump',
        (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      const pending = GatewayRpcElicitationPending(
        requestId: 'elicit_fields_ui',
        title: 'Fund transfer',
        description: 'Approve moving funds?',
        riskLevel: 'high',
        fields: [
          {'name': 'amount', 'value': '500'},
          {'name': 'recipient', 'value': '0xdeadbeef'},
        ],
      );
      gatewayRpcStateController.add(pending);
      await tester.pumpAndSettle();

      expect(find.text('Request Fields'), findsOneWidget);
      expect(find.byKey(const Key('elicitation_field_row_0')), findsOneWidget);
      expect(find.textContaining('amount'), findsOneWidget);
      expect(find.textContaining('0xdeadbeef'), findsOneWidget);
      expect(find.textContaining('elicit_fields_ui'), findsNothing);
      expect(find.textContaining('expires_after'), findsNothing);
    });

    testWidgets(
        'elicitation sheet bounds fields at 10 rows and reports the overflow',
        (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      final fields = [
        for (var i = 0; i < 14; i++) {'name': 'f$i', 'value': 'v$i'},
      ];
      gatewayRpcStateController.add(GatewayRpcElicitationPending(
        requestId: 'elicit_many_fields',
        title: 'Many fields',
        description: 'Overflow demo',
        riskLevel: 'low',
        fields: fields,
      ));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('elicitation_field_row_0')), findsOneWidget);
      expect(find.byKey(const Key('elicitation_field_row_9')), findsOneWidget);
      expect(
          find.byKey(const Key('elicitation_field_row_10')), findsNothing);
      expect(find.text('+4 more'), findsOneWidget);
    });

    testWidgets('truncates an oversized field value to 200 chars',
        (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      final longValue = 'y' * 300;
      gatewayRpcStateController.add(GatewayRpcElicitationPending(
        requestId: 'elicit_long',
        title: 'Long value',
        description: 'Truncation demo',
        riskLevel: 'low',
        fields: [
          {'name': 'payload', 'value': longValue},
        ],
      ));
      await tester.pumpAndSettle();

      final row = tester.widget<Text>(
          find.byKey(const Key('elicitation_field_row_0')));
      final rendered = row.textSpan?.toPlainText() ?? '';
      expect(rendered, 'payload: ${'y' * 200}…');
      expect(rendered.length, lessThan(longValue.length));
    });

    testWidgets('omits the fields section when the request carries none',
        (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      const pending = GatewayRpcElicitationPending(
        requestId: 'elicit_nofields',
        title: 'Plain prompt',
        description: 'Nothing attached',
        riskLevel: 'low',
      );
      gatewayRpcStateController.add(pending);
      await tester.pumpAndSettle();

      expect(find.byType(ElicitationApprovalSheet), findsOneWidget);
      expect(find.text('Request Fields'), findsNothing);
    });

    testWidgets(
        'tapping Approve on elicitation sheet dispatches approval',
        (tester) async {
      when(() => mockGatewayRpcCubit.approveElicitation(
            any(),
            biometricVerified: any(named: 'biometricVerified'),
          )).thenAnswer((_) async {});

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      const pending = GatewayRpcElicitationPending(
        requestId: 'elicit_ui_2',
        title: 'Delete backups',
        description: 'Irreversible wipe requested by Hermes',
        riskLevel: 'medium',
      );
      gatewayRpcStateController.add(pending);
      await tester.pumpAndSettle();

      expect(find.byType(ElicitationApprovalSheet), findsOneWidget);
      expect(find.text('MEDIUM RISK'), findsOneWidget);

      await tester.tap(find.byKey(const Key('elicitation_approve_button')));
      await tester.pumpAndSettle();

      verify(() => mockGatewayRpcCubit.approveElicitation(
            'elicit_ui_2',
            biometricVerified: false,
          )).called(1);
      expect(find.byType(ElicitationApprovalSheet), findsNothing);
    });

    testWidgets(
        'GatewayRpcElicitationResolved closes an open elicitation sheet',
        (tester) async {
      when(() => mockGatewayRpcCubit.rejectElicitation(any()))
          .thenAnswer((_) async {});

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      const pending = GatewayRpcElicitationPending(
        requestId: 'elicit_ui_3',
        title: 'Factory reset',
        description: 'Timed-out demo',
        riskLevel: 'high',
      );
      gatewayRpcStateController.add(pending);
      await tester.pumpAndSettle();
      expect(find.byType(ElicitationApprovalSheet), findsOneWidget);

      gatewayRpcStateController.add(
        const GatewayRpcElicitationResolved(
          requestId: 'elicit_ui_3',
          approved: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ElicitationApprovalSheet), findsNothing);
    });

    testWidgets('tool_event running renders a rolling status line',
        (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'read_file',
        label: 'Reading foo.py',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byKey(const Key('gateway_tool_ticker')), findsOneWidget);
      expect(find.text('Running read_file...'), findsOneWidget);
      expect(find.byKey(const Key('gateway_tool_history')), findsNothing);
    });

    testWidgets('tool_event completed settles the card and drops the running '
        'spinner', (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'read_file',
        label: 'Reading foo.py',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Running read_file...'), findsOneWidget);

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'completed',
        tool: 'read_file',
        label: 'Reading foo.py',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Running read_file...'), findsNothing);
      expect(find.byKey(const Key('gateway_tool_ticker')), findsNothing);
      expect(find.text('1 tool call'), findsOneWidget);

      await tester.tap(find.text('1 tool call'));
      await tester.pumpAndSettle();

      expect(find.text('Tool: read_file'), findsOneWidget);
    });

    testWidgets('tool_event completed without a prior running frame still '
        'renders a card', (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'completed',
        tool: 'read_file',
        label: 'Reading foo.py',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('1 tool call'), findsOneWidget);

      await tester.tap(find.text('1 tool call'));
      await tester.pumpAndSettle();

      expect(find.text('Tool: read_file'), findsOneWidget);
    });

    testWidgets('final assistant message leaves no running spinner behind',
        (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'read_file',
        label: 'Reading foo.py',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Running read_file...'), findsOneWidget);

      gatewayMessageController.add(
          const GatewayChatMessage(content: 'done', role: 'assistant'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.byKey(const Key('gateway_tool_ticker')), findsNothing);
      expect(find.textContaining('Running '), findsNothing);
      expect(find.text('1 tool call'), findsOneWidget);

      await tester.tap(find.text('1 tool call'));
      await tester.pumpAndSettle();

      expect(find.text('Tool: read_file'), findsOneWidget);
    });

    testWidgets('tool_call_request does NOT render a tool card (regression '
        'guard, double-execute)', (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolCallRequestMessage(
        id: 'call_9',
        tool: 'battery_level',
        arguments: {},
      ));
      await tester.pump();

      expect(find.textContaining('Running '), findsNothing);
      expect(find.textContaining('Tool: '), findsNothing);
    });

    testWidgets('tool_event frames are ignored in Direct mode', (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.direct));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'read_file',
        label: 'Reading foo.py',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();

      expect(find.text('Running read_file...'), findsNothing);
    });

    testWidgets('a chat_cancelled error frame settles a running tool card',
        (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'read_file',
        label: 'Reading foo.py',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Running read_file...'), findsOneWidget);

      gatewayMessageController.add(const GatewayErrorMessage(
        message: 'cancelled',
        code: 'chat_cancelled',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Running read_file...'), findsNothing);
      expect(find.byKey(const Key('gateway_tool_ticker')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('1 tool call'), findsOneWidget);

      await tester.tap(find.text('1 tool call'));
      await tester.pumpAndSettle();

      expect(find.text('Tool: read_file'), findsOneWidget);
    });

    testWidgets('a gateway disconnect settles a running tool card',
        (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'read_file',
        label: 'Reading foo.py',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Running read_file...'), findsOneWidget);

      gatewayStateController.add(GatewayConnectionState.disconnected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Running read_file...'), findsNothing);
      expect(find.byKey(const Key('gateway_tool_ticker')), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('1 tool call'), findsOneWidget);

      await tester.tap(find.text('1 tool call'));
      await tester.pumpAndSettle();

      expect(find.text('Tool: read_file'), findsOneWidget);
    });

    testWidgets(
        'a completed frame after the assistant message does not duplicate the '
        'settled card', (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'read_file',
        label: 'Reading foo.py',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      gatewayMessageController.add(
          const GatewayChatMessage(content: 'done', role: 'assistant'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'completed',
        tool: 'read_file',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('1 tool call'), findsOneWidget);

      await tester.tap(find.text('1 tool call'));
      await tester.pumpAndSettle();

      expect(find.text('Tool: read_file'), findsOneWidget);
    });

    testWidgets('an id-less completed frame settles the matching running frame',
        (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'read_file',
        label: 'Reading foo.py',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Running read_file...'), findsOneWidget);

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'completed',
        tool: 'read_file',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('Running read_file...'), findsNothing);
      expect(find.text('1 tool call'), findsOneWidget);

      await tester.tap(find.text('1 tool call'));
      await tester.pumpAndSettle();

      expect(find.text('Tool: read_file'), findsOneWidget);
    });

    testWidgets('the running frame label survives onto the settled card',
        (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'read_file',
        label: 'Reading foo.py',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'completed',
        tool: 'read_file',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.text('1 tool call'), findsOneWidget);

      await tester.tap(find.text('1 tool call'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Tool: read_file'));
      await tester.pumpAndSettle();

      expect(find.text('Reading foo.py'), findsOneWidget);
    });

    testWidgets(
        'switching to Direct after a tool event restores the empty state',
        (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'read_file',
        label: 'Reading foo.py',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Running read_file...'), findsOneWidget);
      expect(find.byKey(const Key('gateway_tool_ticker')), findsOneWidget);
      expect(find.text('Gateway Remote Node'), findsNothing);

      await tester.tap(find.byKey(const Key('chat_mode_toggle')));
      await tester.pumpAndSettle();

      expect(find.text('Running read_file...'), findsNothing);
      expect(find.byKey(const Key('gateway_tool_ticker')), findsNothing);
      expect(find.text('Autonomous Device Agent'), findsOneWidget);
    });

    testWidgets('three running frames render one rolling status line, not '
        'three cards', (tester) async {
      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'read_file',
        label: 'Reading foo.py',
        toolCallId: 'call_1',
        sessionId: 'up-1',
      ));
      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'write_file',
        label: 'Writing bar.py',
        toolCallId: 'call_2',
        sessionId: 'up-1',
      ));
      gatewayMessageController.add(const GatewayToolEventMessage(
        phase: 'running',
        tool: 'grep',
        label: 'Searching baz',
        toolCallId: 'call_3',
        sessionId: 'up-1',
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.textContaining('Running '), findsOneWidget);
      expect(find.text('Running grep...'), findsOneWidget);
      expect(find.text('Running read_file...'), findsNothing);
      expect(find.byKey(const Key('gateway_tool_ticker')), findsOneWidget);

      gatewayMessageController.add(
          const GatewayChatMessage(content: 'done', role: 'assistant'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));

      expect(find.textContaining('Running '), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('3 tool calls'), findsOneWidget);
      expect(find.textContaining('Tool: '), findsNothing);

      await tester.tap(find.text('3 tool calls'));
      await tester.pumpAndSettle();

      expect(find.text('Tool: read_file'), findsOneWidget);
      expect(find.text('Tool: write_file'), findsOneWidget);
      expect(find.text('Tool: grep'), findsOneWidget);
    });
  });
}

class _RecordingBackgroundService implements BackgroundServiceBase {
  final List<String> calls = [];

  @override
  Future<Either<Failure, bool>> startService(
      {String? title, String? content}) async {
    calls.add('startService');
    return const Right(true);
  }

  @override
  Future<Either<Failure, bool>> stopService() async {
    calls.add('stopService');
    return const Right(true);
  }

  @override
  Future<bool> isRunning() async => calls.contains('startService') &&
      !calls.contains('stopService');

  @override
  Future<Either<Failure, bool>> updateNotification({
    required String title,
    required String content,
  }) async {
    calls.add('updateNotification');
    return const Right(true);
  }

  @override
  Future<Either<Failure, bool>> acquireWakeLock({Duration? timeout}) async {
    calls.add('acquireWakeLock');
    return const Right(true);
  }

  @override
  Future<Either<Failure, bool>> releaseWakeLock() async {
    calls.add('releaseWakeLock');
    return const Right(true);
  }

  @override
  Future<bool> isWakeLockHeld() async =>
      calls.contains('acquireWakeLock') && !calls.contains('releaseWakeLock');

  @override
  Future<QuickTileState> getTileState() async => QuickTileState.inactive;

  @override
  Future<Either<Failure, bool>> setTileState(QuickTileState state) async {
    calls.add('setTileState');
    return const Right(true);
  }

  @override
  Future<Either<Failure, TileStateChange>> toggleTileState() async {
    calls.add('toggleTileState');
    return const Right(TileStateChange(
      state: QuickTileState.inactive,
      changed: true,
      reason: 'toggled',
    ));
  }

  @override
  Stream<String> get actionStream => const Stream<String>.empty();

  @override
  Future<String?> getPendingAction() async => null;

  @override
  Future<void> clearPendingAction() async {
    calls.add('clearPendingAction');
  }

  @override
  void dispose() {
    calls.add('dispose');
  }
}
