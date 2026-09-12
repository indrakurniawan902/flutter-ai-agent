import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_client.dart';
import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_socket.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/device_context_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/pairing_parser.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_approval_sheet.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_rpc_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/pairing/qr_scanner_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

class FakeGatewaySocket implements GatewaySocket {
  final StreamController<dynamic> controller;
  final List<String> sent;

  FakeGatewaySocket(this.controller, this.sent);

  @override
  Stream<dynamic> get stream => controller.stream;

  @override
  void send(String data) {
    sent.add(data);
    if (data.contains('"type":"auth"')) {
      controller.add(jsonEncode({
        'type': 'auth_success',
        'session_id': 'sess_fase2_e2e_node',
      }));
    } else if (data.contains('"type":"ping"')) {
      try {
        final decoded = jsonDecode(data) as Map<String, dynamic>;
        controller.add(jsonEncode({
          'type': 'pong',
          'timestamp': decoded['timestamp'],
        }));
      } catch (_) {}
    }
  }

  @override
  Future<void> close([int? code, String? reason]) => Future.value();

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;
}

class FakeGatewaySocketFactory implements GatewaySocketFactory {
  final GatewaySocket socket;

  FakeGatewaySocketFactory(this.socket);

  @override
  Future<GatewaySocket> connect(
    Uri uri, {
    Map<String, dynamic>? headers,
    Duration? timeout,
    Duration? pingInterval,
  }) =>
      Future.value(socket);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockFlutterSecureStorage mockSecureStorage;
  late FakeGatewaySocket fakeSocket;
  late FakeGatewaySocketFactory fakeSocketFactory;
  late MockClipboardService mockClipboardService;
  late MockDeviceContextService mockDeviceContextService;
  late MockNotificationService mockNotificationService;
  late MockLlmRepository mockLlmRepository;

  late StreamController<dynamic> socketStreamController;
  late List<String> sentFrames;
  late Map<String, String> inMemoryStorage;

  setUpAll(() {
    registerFallbackValue(Uri.parse('ws://192.168.1.50:18789/ws'));
  });

  setUp(() async {
    await sl.reset();
    inMemoryStorage = {};
    sentFrames = [];

    mockSecureStorage = MockFlutterSecureStorage();
    mockClipboardService = MockClipboardService();
    mockDeviceContextService = MockDeviceContextService();
    mockNotificationService = MockNotificationService();
    mockLlmRepository = MockLlmRepository();

    socketStreamController = StreamController<dynamic>.broadcast();
    fakeSocket = FakeGatewaySocket(socketStreamController, sentFrames);
    fakeSocketFactory = FakeGatewaySocketFactory(fakeSocket);

    when(() => mockSecureStorage.read(key: any(named: 'key')))
        .thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      return inMemoryStorage[key];
    });

    when(() => mockSecureStorage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((invocation) async {
      final key = invocation.namedArguments[#key] as String;
      final value = invocation.namedArguments[#value] as String;
      inMemoryStorage[key] = value;
    });

    when(() => mockSecureStorage.deleteAll())
        .thenAnswer((_) async => inMemoryStorage.clear());

    sl.registerLazySingleton<FlutterSecureStorage>(() => mockSecureStorage);
    sl.registerLazySingleton<SecureStorageService>(
      () => SecureStorageService(storage: mockSecureStorage),
    );
    sl.registerLazySingleton<LlmRepository>(() => mockLlmRepository);
    sl.registerLazySingleton<ClipboardServiceBase>(() => mockClipboardService);
    sl.registerLazySingleton<LocationServiceBase>(() => MockLocationService());
    sl.registerLazySingleton<DeviceContextServiceBase>(
      () => mockDeviceContextService,
    );
    sl.registerLazySingleton<CameraVisionServiceBase>(
      () => MockCameraVisionService(),
    );
    sl.registerLazySingleton<CalendarServiceBase>(() => MockCalendarService());
    sl.registerLazySingleton<NotificationServiceBase>(
      () => mockNotificationService,
    );

    final toolRegistry = ToolRegistry();
    toolRegistry.registerClipboardTools(mockClipboardService);
    toolRegistry.registerDeviceContextTools(mockDeviceContextService);
    toolRegistry.registerNotificationTools(mockNotificationService);
    sl.registerLazySingleton<ToolRegistry>(() => toolRegistry);

    sl.registerLazySingleton<PairingParser>(() => const PairingParser());
    sl.registerLazySingleton<GatewaySocketFactory>(() => fakeSocketFactory);

    final gatewayClient = GatewayClient(
      socketFactory: sl<GatewaySocketFactory>(),
      options: const GatewayClientOptions(
        heartbeatInterval: Duration(minutes: 30),
        heartbeatTimeout: Duration(minutes: 30),
        authTimeout: Duration(seconds: 10),
        connectTimeout: Duration(seconds: 10),
        initialReconnectDelay: Duration(seconds: 5),
        maxReconnectDelay: Duration(seconds: 10),
      ),
    );
    sl.registerLazySingleton<GatewayClient>(() => gatewayClient);
    sl.registerLazySingleton<GatewayClientBase>(() => gatewayClient);

    sl.registerLazySingleton<GatewayRpcReceiverBase>(
      () => GatewayDeviceRpcReceiver(
        gatewayClient: sl<GatewayClientBase>(),
        toolRegistry: sl<ToolRegistry>(),
      ),
    );

    sl.registerLazySingleton<GatewayRpcCubit>(
      () => GatewayRpcCubit(
        gatewayClient: sl<GatewayClientBase>(),
        toolRegistry: sl<ToolRegistry>(),
        rpcReceiver: sl<GatewayRpcReceiverBase>(),
      ),
    );

    sl.registerFactory<ServerProfileCubit>(
      () =>
          ServerProfileCubit(secureStorageService: sl<SecureStorageService>()),
    );

    sl.registerFactory<SettingsCubit>(
      () => SettingsCubit(secureStorageService: sl<SecureStorageService>()),
    );

    sl.registerFactory<AgentCubit>(
      () => AgentCubit(
        llmRepository: sl<LlmRepository>(),
        toolRegistry: sl<ToolRegistry>(),
        secureStorageService: sl<SecureStorageService>(),
      ),
    );
  });

  tearDown(() async {
    if (sl.isRegistered<GatewayClient>()) {
      await sl<GatewayClient>().disconnect();
    }
    if (!socketStreamController.isClosed) {
      await socketStreamController.close();
    }
    await sl.reset();
  });

  Widget buildTestApp({
    Widget Function(BuildContext context)? qrScannerBuilder,
  }) {
    return MaterialApp(
      home: ChatScreen(
        qrScannerBuilder: qrScannerBuilder ??
            (context) => QrScannerScreen(
                  currentTime: DateTime.now().toUtc(),
                  scannerWidgetBuilder: (ctx, onDetect) => const SizedBox(),
                ),
      ),
    );
  }

  group('Fase 2 Gateway E2E Integration Tests', () {
    testWidgets(
      'Full Gateway E2E Flow: QR Scan -> Pairing Handshake -> Server sends prompt -> Mobile executes Tier 1 device tool -> Server receives result',
      (tester) async {
        when(() => mockClipboardService.clipboardRead())
            .thenAnswer((_) async => const Right('Hermes Authentication Secret'));

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        expect(find.text('Flames'), findsOneWidget);
        expect(find.text('Standalone'), findsOneWidget);
        expect(find.byKey(const Key('chat_qr_scan_button')), findsOneWidget);

        await tester.tap(find.byKey(const Key('chat_qr_scan_button')));
        await tester.pumpAndSettle();

        expect(find.byType(QrScannerScreen), findsOneWidget);
        expect(find.text('Scan Pairing Code'), findsOneWidget);

        await tester.tap(find.byKey(const Key('qr_manual_input_button')));
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('manual_input_dialog')), findsOneWidget);

        final pairingJson = jsonEncode({
          'gatewayUrl': 'http://192.168.1.50:18789',
          'token': 'tok_gateway_handshake_secret_123',
          'profileName': 'Hermes Central Node',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await tester.enterText(
          find.byKey(const Key('manual_input_textfield')),
          pairingJson,
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('manual_input_submit_button')));
        await tester.pumpAndSettle();

        expect(find.byType(QrScannerScreen), findsNothing);
        expect(find.text('Paired with Hermes Central Node'), findsOneWidget);

        final authFrame = sentFrames.firstWhere(
          (f) =>
              f.contains('"type":"auth"') &&
              f.contains('tok_gateway_handshake_secret_123'),
        );
        expect(authFrame, isNotEmpty);

        expect(find.text('Connected'), findsOneWidget);

        socketStreamController.add(jsonEncode({
          'type': 'tool_call_request',
          'id': 'rpc_call_clip_001',
          'tool': 'clipboard_read',
          'arguments': <String, dynamic>{},
        }));

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        verify(() => mockClipboardService.clipboardRead()).called(1);

        final responseFrameStr = sentFrames.firstWhere(
          (f) =>
              f.contains('"type":"tool_call_response"') &&
              f.contains('rpc_call_clip_001'),
        );
        expect(responseFrameStr, isNotEmpty);

        final decodedResponse =
            jsonDecode(responseFrameStr) as Map<String, dynamic>;
        expect(decodedResponse['id'], 'rpc_call_clip_001');
        expect(decodedResponse['error'], isNull);
        expect(
          decodedResponse['result'].toString(),
          contains('Hermes Authentication Secret'),
        );

        await sl<GatewayClient>().disconnect();
        await tester.pump();
      },
    );

    testWidgets(
      'Gateway Tier 3 HITL Gate: Server sends dangerous tool call -> ActionApprovalSheet appears -> User Approves -> Tool executes -> Server receives result',
      (tester) async {
        when(() => mockNotificationService.scheduleReminder(
              title: any(named: 'title'),
              body: any(named: 'body'),
              delayMinutes: any(named: 'delayMinutes'),
            )).thenAnswer((_) async => const Right(null));

        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('chat_qr_scan_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('qr_manual_input_button')));
        await tester.pumpAndSettle();

        final pairingJson = jsonEncode({
          'gatewayUrl': 'http://192.168.1.50:18789',
          'token': 'tok_hitl_test',
          'profileName': 'HITL Node',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await tester.enterText(
          find.byKey(const Key('manual_input_textfield')),
          pairingJson,
        );
        await tester.tap(find.byKey(const Key('manual_input_submit_button')));
        await tester.pumpAndSettle();

        expect(find.text('Connected'), findsOneWidget);

        socketStreamController.add(jsonEncode({
          'type': 'tool_call_request',
          'id': 'rpc_call_hitl_101',
          'tool': 'schedule_reminder',
          'arguments': {
            'title': 'Board Meeting Reminder',
            'body': 'Room 402',
            'delayMinutes': 30,
          },
        }));

        await tester.pumpAndSettle();

        expect(find.byType(ActionApprovalSheet), findsOneWidget);
        expect(find.text('Action Approval Required'), findsOneWidget);
        expect(find.text('schedule_reminder'), findsOneWidget);
        expect(find.textContaining('Board Meeting Reminder'), findsWidgets);

        verifyNever(() => mockNotificationService.scheduleReminder(
              title: any(named: 'title'),
              body: any(named: 'body'),
              delayMinutes: any(named: 'delayMinutes'),
            ));

        await tester.tap(find.text('Approve'));
        await tester.pumpAndSettle();

        expect(find.byType(ActionApprovalSheet), findsNothing);
        verify(() => mockNotificationService.scheduleReminder(
              title: 'Board Meeting Reminder',
              body: 'Room 402',
              delayMinutes: 30,
            )).called(1);

        final responseFrameStr = sentFrames.firstWhere(
          (f) =>
              f.contains('"type":"tool_call_response"') &&
              f.contains('rpc_call_hitl_101'),
        );
        final decodedResponse =
            jsonDecode(responseFrameStr) as Map<String, dynamic>;
        expect(decodedResponse['id'], 'rpc_call_hitl_101');
        expect(decodedResponse['error'], isNull);

        await sl<GatewayClient>().disconnect();
        await tester.pump();
      },
    );

    testWidgets(
      'Gateway Tier 3 HITL Gate Rejection: Server sends dangerous tool call -> User Rejects -> Tool does not execute -> Server receives rejection error',
      (tester) async {
        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('chat_qr_scan_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('qr_manual_input_button')));
        await tester.pumpAndSettle();

        final pairingJson = jsonEncode({
          'gatewayUrl': 'http://192.168.1.50:18789',
          'token': 'tok_reject_test',
          'profileName': 'Reject Node',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await tester.enterText(
          find.byKey(const Key('manual_input_textfield')),
          pairingJson,
        );
        await tester.tap(find.byKey(const Key('manual_input_submit_button')));
        await tester.pumpAndSettle();

        expect(find.text('Connected'), findsOneWidget);

        socketStreamController.add(jsonEncode({
          'type': 'tool_call_request',
          'id': 'rpc_call_hitl_102',
          'tool': 'schedule_reminder',
          'arguments': {
            'title': 'Unwanted Alarm',
            'body': 'Cancel immediate',
            'delayMinutes': 5,
          },
        }));

        await tester.pumpAndSettle();

        expect(find.byType(ActionApprovalSheet), findsOneWidget);
        expect(find.text('Action Approval Required'), findsOneWidget);
        expect(find.text('schedule_reminder'), findsOneWidget);

        await tester.tap(find.text('Reject'));
        await tester.pumpAndSettle();

        expect(find.byType(ActionApprovalSheet), findsNothing);
        verifyNever(() => mockNotificationService.scheduleReminder(
              title: any(named: 'title'),
              body: any(named: 'body'),
              delayMinutes: any(named: 'delayMinutes'),
            ));

        final responseFrameStr = sentFrames.firstWhere(
          (f) =>
              f.contains('"type":"tool_call_response"') &&
              f.contains('rpc_call_hitl_102'),
        );
        final decodedResponse =
            jsonDecode(responseFrameStr) as Map<String, dynamic>;
        expect(decodedResponse['id'], 'rpc_call_hitl_102');
        expect(decodedResponse['error'], contains('rejected by user'));

        await sl<GatewayClient>().disconnect();
        await tester.pump();
      },
    );

    testWidgets(
      'Gateway Bidirectional Chat & Streaming: User prompt -> Server chat frame -> Streaming text delta -> Final assistant message rendered',
      (tester) async {
        await tester.pumpWidget(buildTestApp());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('chat_qr_scan_button')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('qr_manual_input_button')));
        await tester.pumpAndSettle();

        final pairingJson = jsonEncode({
          'gatewayUrl': 'http://192.168.1.50:18789',
          'token': 'tok_chat_test',
          'profileName': 'Chat Node',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        await tester.enterText(
          find.byKey(const Key('manual_input_textfield')),
          pairingJson,
        );
        await tester.tap(find.byKey(const Key('manual_input_submit_button')));
        await tester.pumpAndSettle();

        expect(find.text('Connected'), findsOneWidget);

        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('chat_input_field')),
          'Check system health and battery status',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('chat_send_button')));
        await tester.pumpAndSettle();

        expect(
            find.text('Check system health and battery status'), findsOneWidget);
        final chatFrameStr = sentFrames.firstWhere(
          (f) =>
              f.contains('"type":"chat_message"') &&
              f.contains('Check system health and battery status'),
        );
        expect(chatFrameStr, isNotEmpty);

        socketStreamController.add(jsonEncode({
          'type': 'text_delta',
          'delta': 'System diagnostics: ',
        }));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is MarkdownBody &&
                w.data.contains('System diagnostics: '),
          ),
          findsOneWidget,
        );

        socketStreamController.add(jsonEncode({
          'type': 'text_delta',
          'delta': 'All hardware sensors active.',
        }));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(
          find.byWidgetPredicate(
            (w) =>
                w is MarkdownBody &&
                w.data.contains(
                    'System diagnostics: All hardware sensors active.'),
          ),
          findsOneWidget,
        );

        socketStreamController.add(jsonEncode({
          'type': 'chat_message',
          'role': 'assistant',
          'content': 'System diagnostics: All hardware sensors active.',
        }));
        await tester.pumpAndSettle();

        expect(
          find.byWidgetPredicate(
            (w) =>
                w is MarkdownBody &&
                w.data.contains(
                    'System diagnostics: All hardware sensors active.'),
          ),
          findsOneWidget,
        );

        await sl<GatewayClient>().disconnect();
        await tester.pump();
      },
    );

    testWidgets(
      'Gateway Camera QR Code Scan Simulation: Camera scanner detects QR -> Auto-connects and completes handshake',
      (tester) async {
        when(() => mockDeviceContextService.deviceStatusFormattedJson())
            .thenAnswer(
          (_) async =>
              const Right('{"battery": 88, "charging": false, "connectivity": "wifi"}'),
        );

        final pairingJson = jsonEncode({
          'gatewayUrl': 'http://192.168.1.50:18789',
          'token': 'tok_camera_scan_123',
          'profileName': 'Camera Node',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
        });

        void Function(String)? triggerScan;

        await tester.pumpWidget(
          buildTestApp(
            qrScannerBuilder: (context) => QrScannerScreen(
              currentTime: DateTime.now().toUtc(),
              scannerWidgetBuilder: (ctx, onDetect) {
                triggerScan = onDetect;
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('chat_qr_scan_button')));
        await tester.pumpAndSettle();

        expect(triggerScan, isNotNull);
        triggerScan!(pairingJson);
        await tester.pumpAndSettle();

        expect(find.text('Paired with Camera Node'), findsOneWidget);
        expect(find.text('Connected'), findsOneWidget);

        socketStreamController.add(jsonEncode({
          'type': 'tool_call_request',
          'id': 'rpc_device_001',
          'tool': 'device_status',
          'arguments': <String, dynamic>{},
        }));

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        verify(() => mockDeviceContextService.deviceStatusFormattedJson())
            .called(1);

        final responseFrameStr = sentFrames.firstWhere(
          (f) =>
              f.contains('"type":"tool_call_response"') &&
              f.contains('rpc_device_001'),
        );
        final decodedResponse =
            jsonDecode(responseFrameStr) as Map<String, dynamic>;
        expect(decodedResponse['id'], 'rpc_device_001');
        expect(decodedResponse['result']['battery'], 88);

        await sl<GatewayClient>().disconnect();
        await tester.pump();
      },
    );
  });
}
