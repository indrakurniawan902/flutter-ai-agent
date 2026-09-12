import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_mode.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/models/chat/tool_call_request.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_approval_sheet.dart';
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

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
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
    await sl.reset();
  });

  Widget createWidgetUnderTest({
    ChatMode initialMode = ChatMode.direct,
  }) {
    return MaterialApp(
      home: ChatScreen(
        initialMode: initialMode,
        gatewayClient: mockGatewayClient,
        gatewayRpcCubit: mockGatewayRpcCubit,
        serverProfileCubit: mockServerProfileCubit,
      ),
    );
  }

  group('ChatScreen Gateway - Connection Status Indicator', () {
    testWidgets('renders Standalone with Grey LED dot in Direct mode',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(initialMode: ChatMode.direct));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_connection_indicator')), findsOneWidget);
      expect(find.text('Standalone'), findsOneWidget);

      final ledDot =
          tester.widget<Container>(find.byKey(const Key('connection_led_dot')));
      final decoration = ledDot.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF94A3B8));
    });

    testWidgets(
        'renders Connected with Green LED dot in Gateway mode when connected',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.connected);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_connection_indicator')), findsOneWidget);
      expect(find.text('Connected'), findsOneWidget);

      final ledDot =
          tester.widget<Container>(find.byKey(const Key('connection_led_dot')));
      final decoration = ledDot.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF22C55E));
    });

    testWidgets(
        'renders Reconnecting with Amber LED dot in Gateway mode when reconnecting',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.reconnecting);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_connection_indicator')), findsOneWidget);
      expect(find.text('Reconnecting'), findsOneWidget);

      final ledDot =
          tester.widget<Container>(find.byKey(const Key('connection_led_dot')));
      final decoration = ledDot.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFFF59E0B));
    });

    testWidgets(
        'renders Connecting with Amber LED dot in Gateway mode when connecting',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.connecting);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_connection_indicator')), findsOneWidget);
      expect(find.text('Connecting'), findsOneWidget);

      final ledDot =
          tester.widget<Container>(find.byKey(const Key('connection_led_dot')));
      final decoration = ledDot.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFFF59E0B));
    });

    testWidgets(
        'renders Disconnected with Grey LED dot in Gateway mode when disconnected',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.disconnected);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_connection_indicator')), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);

      final ledDot =
          tester.widget<Container>(find.byKey(const Key('connection_led_dot')));
      final decoration = ledDot.decoration as BoxDecoration;
      expect(decoration.color, const Color(0xFF94A3B8));
    });

    testWidgets('dynamically updates indicator on gateway stateStream transition',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.disconnected);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();
      expect(find.text('Disconnected'), findsOneWidget);

      gatewayStateController.add(GatewayConnectionState.connecting);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Connecting'), findsOneWidget);

      gatewayStateController.add(GatewayConnectionState.connected);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Connected'), findsOneWidget);

      gatewayStateController.add(GatewayConnectionState.reconnecting);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
      expect(find.text('Reconnecting'), findsOneWidget);
    });

    testWidgets('tapping connection indicator displays connection details dialog',
        (tester) async {
      when(() => mockGatewayClient.state)
          .thenReturn(GatewayConnectionState.connected);

      await tester.pumpWidget(
          createWidgetUnderTest(initialMode: ChatMode.gateway));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_connection_indicator')));
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
  });
}
