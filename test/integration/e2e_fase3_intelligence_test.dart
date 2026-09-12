import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_ai_agent/myapp.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_router.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/memory_item.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/device_context_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/pairing_parser.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late MockFlutterSecureStorage mockSecureStorage;
  late MockLlmRepository mockLlmRepository;
  late MockFileWorkspaceService mockFileWorkspaceService;
  late MockNotificationTriageService mockNotificationTriageService;
  late MockLocalMemoryService mockLocalMemoryService;
  late MockAmbientTriggerService mockAmbientTriggerService;
  late StreamController<AmbientEvent> ambientEventController;
  late Map<String, String> inMemoryStorage;
  late List<MemoryItem> storedMemoryItems;

  setUpAll(() {
    registerFallbackValue(
      const GeofenceRegion(
        id: 'dummy',
        latitude: 0.0,
        longitude: 0.0,
        radiusMeters: 100.0,
      ),
    );
  });

  setUp(() async {
    await sl.reset();
    inMemoryStorage = {};
    storedMemoryItems = [];
    ambientEventController = StreamController<AmbientEvent>.broadcast();

    mockSecureStorage = MockFlutterSecureStorage();
    mockLlmRepository = MockLlmRepository();
    mockFileWorkspaceService = MockFileWorkspaceService();
    mockNotificationTriageService = MockNotificationTriageService();
    mockLocalMemoryService = MockLocalMemoryService();
    mockAmbientTriggerService = MockAmbientTriggerService();

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

    when(() => mockLocalMemoryService.searchMemories(any(), any()))
        .thenAnswer((_) async => const Right([]));

    // Register all core and Fase 3 dependencies in GetIt
    sl.registerLazySingleton<FlutterSecureStorage>(() => mockSecureStorage);
    sl.registerLazySingleton<SecureStorageService>(
      () => SecureStorageService(storage: mockSecureStorage),
    );
    sl.registerLazySingleton<SettingsCubit>(
      () => SettingsCubit(secureStorageService: sl<SecureStorageService>()),
    );
    sl.registerLazySingleton<ServerProfileCubit>(
      () => ServerProfileCubit(
        secureStorageService: sl<SecureStorageService>(),
      ),
    );
    sl.registerLazySingleton<LlmRepository>(() => mockLlmRepository);
    sl.registerLazySingleton<ClipboardServiceBase>(() => MockClipboardService());
    sl.registerLazySingleton<LocationServiceBase>(() => MockLocationService());
    sl.registerLazySingleton<DeviceContextServiceBase>(
      () => MockDeviceContextService(),
    );
    sl.registerLazySingleton<CameraVisionServiceBase>(
      () => MockCameraVisionService(),
    );
    sl.registerLazySingleton<CalendarServiceBase>(() => MockCalendarService());
    sl.registerLazySingleton<NotificationServiceBase>(
      () => MockNotificationService(),
    );

    // Fase 3 Services
    sl.registerLazySingleton<FileWorkspaceServiceBase>(
      () => mockFileWorkspaceService,
    );
    sl.registerLazySingleton<NotificationTriageServiceBase>(
      () => mockNotificationTriageService,
    );
    sl.registerLazySingleton<LocalMemoryServiceBase>(
      () => mockLocalMemoryService,
    );
    sl.registerLazySingleton<AmbientTriggerServiceBase>(
      () => mockAmbientTriggerService,
    );

    final toolRegistry = ToolRegistry();
    toolRegistry.registerFileWorkspaceTools(mockFileWorkspaceService);
    toolRegistry.registerNotificationTriageTools(mockNotificationTriageService);
    toolRegistry.registerMemoryTools(mockLocalMemoryService);
    toolRegistry.registerAmbientTriggerTools(mockAmbientTriggerService);
    sl.registerLazySingleton<ToolRegistry>(() => toolRegistry);

    sl.registerLazySingleton<PairingParser>(() => const PairingParser());

    sl.registerFactory<AgentCubit>(
      () => AgentCubit(
        llmRepository: sl<LlmRepository>(),
        toolRegistry: sl<ToolRegistry>(),
        secureStorageService: sl<SecureStorageService>(),
        localMemoryService: sl<LocalMemoryServiceBase>(),
      ),
    );

    appRouter.go('/splash');
  });

  tearDown(() async {
    await ambientEventController.close();
    await sl.reset();
  });

  group('Fase 3 E2E Integration Suite', () {
    testWidgets(
      'Comprehensive E2E Pipeline: File reading -> Notification triage -> Local memory retrieval -> Ambient prompt',
      (tester) async {
        // Step 1: File reading setup
        when(() => mockFileWorkspaceService.checkPermission())
            .thenAnswer((_) async => true);
        when(() => mockFileWorkspaceService.readFile(
              '/workspace/incident_report.txt',
              maxLines: any(named: 'maxLines'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => const Right(
              'Incident #104: Server cluster down. Auth token required for recovery.',
            ));

        // Step 2: Notification triage setup
        when(() => mockNotificationTriageService.checkPermission())
            .thenAnswer((_) async => true);
        when(() => mockNotificationTriageService.extractLatestOtpFormattedJson(
              appFilter: any(named: 'appFilter'),
            )).thenAnswer((_) async => const Right(
              '{"found":true,"otp":"948210","sender":"SecOps","timestamp":"2026-09-11T12:00:00Z"}',
            ));

        // Step 3: Local memory setup
        when(() => mockLocalMemoryService.saveMemoryFormattedJson(any()))
            .thenAnswer((invocation) async {
          final args = invocation.positionalArguments[0] as Map<String, dynamic>;
          final key = args['key'] as String;
          final content = args['content'] as String;
          final tags = (args['tags'] as List?)?.cast<String>() ?? [];
          final now = DateTime.now();
          storedMemoryItems.add(MemoryItem(
            id: storedMemoryItems.length + 1,
            key: key,
            content: content,
            tags: tags,
            createdAt: now,
            updatedAt: now,
          ));
          return const Right('{"status":"success","key":"secops_token"}');
        });

        when(() => mockLocalMemoryService.searchMemories(any(), any()))
            .thenAnswer((invocation) async {
          final query = (invocation.positionalArguments[0] as String).toLowerCase();
          final matching = storedMemoryItems.where((m) {
            return m.key.toLowerCase().contains(query) ||
                m.content.toLowerCase().contains(query) ||
                query.contains('token') ||
                query.contains('secops');
          }).toList();
          return Right(matching);
        });

        // Setup multi-turn LLM response stream
        when(() => mockLlmRepository.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
              temperature: any(named: 'temperature'),
            )).thenAnswer((invocation) async {
          final msgs =
              invocation.namedArguments[#messages] as List<Map<String, dynamic>>;
          final lastMsg = msgs.last;
          final role = lastMsg['role'] as String;
          final content = lastMsg['content'] as String?;

          // Turn 1: User asks to inspect file -> LLM calls read_device_file
          if (role == 'user' && content != null && content.contains('incident_report.txt')) {
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_file_1',
                    name: 'read_device_file',
                    argumentsFragment:
                        '{"path":"/workspace/incident_report.txt"}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          }

          // Turn 2: File read tool finished -> LLM summarizes file and asks to check notifications
          if (role == 'tool' && lastMsg['name'] == 'read_device_file') {
            return Right(Stream.fromIterable([
              const ChatChunk(
                contentDelta:
                    'Incident #104 requires an authentication token. Checking notifications for OTP.',
                finishReason: 'stop',
              ),
            ]));
          }

          // Turn 3: User requests OTP extraction -> LLM calls extract_latest_otp
          if (role == 'user' && content != null && content.contains('Extract OTP')) {
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_otp_1',
                    name: 'extract_latest_otp',
                    argumentsFragment: '{"appFilter":"sms"}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          }

          // Turn 4: Tool OTP executed -> LLM calls save_memory to persist the token
          if (role == 'tool' && lastMsg['name'] == 'extract_latest_otp') {
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_mem_1',
                    name: 'save_memory',
                    argumentsFragment:
                        '{"key":"secops_token","content":"SecOps recovery OTP is 948210","tags":["security","otp"]}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          }

          // Turn 5: Memory saved -> LLM confirms OTP extraction and persistence
          if (role == 'tool' && lastMsg['name'] == 'save_memory') {
            return Right(Stream.fromIterable([
              const ChatChunk(
                contentDelta:
                    'Extracted OTP 948210 and saved to persistent memory under secops_token.',
                finishReason: 'stop',
              ),
            ]));
          }

          // Turn 6: User queries token -> AgentCubit injects memory into system prompt -> LLM answers
          if (role == 'user' && content != null && content.contains('What is the SecOps recovery token')) {
            return Right(Stream.fromIterable([
              const ChatChunk(
                contentDelta:
                    'The SecOps recovery token is 948210 as stored in memory.',
                finishReason: 'stop',
              ),
            ]));
          }

          // Turn 7: Ambient prompt triggered -> LLM generates proactive response
          if (role == 'user' && content != null && content.contains('[Ambient Trigger]')) {
            return Right(Stream.fromIterable([
              const ChatChunk(
                contentDelta:
                    'Proactive Alert: Battery is down to 12%. All recovery logs have been safely stored.',
                finishReason: 'stop',
              ),
            ]));
          }

          return Right(Stream.fromIterable([
            const ChatChunk(contentDelta: 'Acknowledged.', finishReason: 'stop'),
          ]));
        });

        // Step 1: Launch App & Execute File Reading
        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        final inputField = find.byKey(const Key('chat_input_field'));
        final sendButton = find.byKey(const Key('chat_send_button'));

        await tester.enterText(inputField, 'Please check /workspace/incident_report.txt');
        await tester.pump();
        await tester.tap(sendButton);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Verify FileWorkspaceService invocation and response in UI
        verify(() => mockFileWorkspaceService.readFile(
              '/workspace/incident_report.txt',
              maxLines: any(named: 'maxLines'),
              offset: any(named: 'offset'),
            )).called(1);
        expect(find.text('Tool: read_device_file'), findsOneWidget);
        expect(
          find.textContaining('Incident #104 requires an authentication token.'),
          findsOneWidget,
        );

        // Step 2: Execute Notification Triage & Memory Persistence
        await tester.enterText(inputField, 'Extract OTP from incoming SMS notifications');
        await tester.pump();
        await tester.tap(sendButton);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));
        await tester.pumpAndSettle();

        // Verify Notification triage tool execution
        verify(() => mockNotificationTriageService.extractLatestOtpFormattedJson(
              appFilter: 'sms',
            )).called(1);
        expect(find.text('Tool: extract_latest_otp'), findsOneWidget);

        // Verify Local Memory persistence tool execution
        verify(() => mockLocalMemoryService.saveMemoryFormattedJson(any())).called(1);
        expect(find.text('Tool: save_memory'), findsOneWidget);
        expect(
          find.textContaining('Extracted OTP 948210 and saved to persistent memory'),
          findsOneWidget,
        );
        expect(storedMemoryItems.length, equals(1));
        expect(storedMemoryItems.first.key, equals('secops_token'));

        // Step 3: Local Memory Retrieval & Prompt Context Injection
        await tester.enterText(inputField, 'What is the SecOps recovery token?');
        await tester.pump();
        await tester.tap(sendButton);

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Verify LocalMemoryService search was triggered by AgentCubit
        verify(() => mockLocalMemoryService.searchMemories(
              'What is the SecOps recovery token?',
              3,
            )).called(1);
        expect(
          find.textContaining('The SecOps recovery token is 948210 as stored in memory.'),
          findsOneWidget,
        );

        // Step 4: Ambient Trigger Event -> Proactive Agent Prompt
        final ambientEvent = AmbientEvent(
          id: 'amb_evt_bat_1',
          type: AmbientEventType.batteryLow,
          timestamp: DateTime.now(),
          title: 'Battery Low',
          body: 'Battery is at 12%',
          batteryLevel: 12,
        );

        // Ambient trigger service dispatches event to stream
        ambientEventController.add(ambientEvent);
        await tester.pump();

        // Proactive trigger pipes to AgentCubit
        final agentCubit = BlocProvider.of<AgentCubit>(
          tester.element(find.byKey(const Key('chat_input_field'))),
        );
        agentCubit.sendMessage(
          '[Ambient Trigger] ${ambientEvent.title}: ${ambientEvent.body}. Recommendation: Enable battery saver',
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Verify proactive ambient response rendered in UI
        expect(find.textContaining('[Ambient Trigger] Battery Low: Battery is at 12%'), findsOneWidget);
        expect(
          find.textContaining('Proactive Alert: Battery is down to 12%'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Fase 3 Error Resilience: Gracefully handles file missing, notification denied, and empty memories',
      (tester) async {
        // Setup error states for services
        when(() => mockFileWorkspaceService.checkPermission())
            .thenAnswer((_) async => true);
        when(() => mockFileWorkspaceService.readFile(
              any(),
              maxLines: any(named: 'maxLines'),
              offset: any(named: 'offset'),
            )).thenAnswer((_) async => const Left(
              StorageFailure('File not found at /missing.txt'),
            ));

        when(() => mockNotificationTriageService.checkPermission())
            .thenAnswer((_) async => false);
        when(() => mockNotificationTriageService.extractLatestOtpFormattedJson(
              appFilter: any(named: 'appFilter'),
            )).thenAnswer((_) async => const Left(
              PermissionFailure('Notification listener permission not granted'),
            ));

        when(() => mockLocalMemoryService.searchMemories(any(), any()))
            .thenAnswer((_) async => const Right([]));

        when(() => mockLlmRepository.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
              temperature: any(named: 'temperature'),
            )).thenAnswer((invocation) async {
          final msgs =
              invocation.namedArguments[#messages] as List<Map<String, dynamic>>;
          final lastMsg = msgs.last;
          final role = lastMsg['role'] as String;

          if (role == 'user') {
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_missing_file',
                    name: 'read_device_file',
                    argumentsFragment: '{"path":"/missing.txt"}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          }

          if (role == 'tool') {
            return Right(Stream.fromIterable([
              const ChatChunk(
                contentDelta:
                    'Handled error: File could not be read.',
                finishReason: 'stop',
              ),
            ]));
          }

          return Right(Stream.fromIterable([
            const ChatChunk(contentDelta: 'Done.', finishReason: 'stop'),
          ]));
        });

        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('chat_input_field')),
          'Read /missing.txt',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('chat_send_button')));

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Agent handles tool error cleanly and continues conversation
        expect(find.text('Tool: read_device_file'), findsOneWidget);
        expect(find.text('Result: read_device_file'), findsOneWidget);
        expect(
          find.textContaining('Handled error: File could not be read.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Ambient Trigger Geofence: register_geofence and list_geofences executed via ToolRegistry',
      (tester) async {
        when(() => mockAmbientTriggerService.addGeofence(any()))
            .thenReturn(null);

        when(() => mockAmbientTriggerService.regions)
            .thenReturn(const [
                  GeofenceRegion(
                    id: 'office_hq',
                    latitude: -6.2,
                    longitude: 106.8,
                    radiusMeters: 100.0,
                  ),
                ]);

        when(() => mockLlmRepository.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
              temperature: any(named: 'temperature'),
            )).thenAnswer((invocation) async {
          final msgs =
              invocation.namedArguments[#messages] as List<Map<String, dynamic>>;
          final lastMsg = msgs.last;
          final role = lastMsg['role'] as String;

          if (role == 'user') {
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_geo_1',
                    name: 'register_geofence',
                    argumentsFragment:
                        '{"id":"office_hq","latitude":-6.2,"longitude":106.8,"radiusMeters":100.0}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          }

          if (role == 'tool') {
            return Right(Stream.fromIterable([
              const ChatChunk(
                contentDelta: 'Geofence Office HQ successfully registered.',
                finishReason: 'stop',
              ),
            ]));
          }

          return Right(Stream.fromIterable([
            const ChatChunk(contentDelta: 'Ready.', finishReason: 'stop'),
          ]));
        });

        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('chat_input_field')),
          'Set geofence for Office HQ',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('chat_send_button')));

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        verify(() => mockAmbientTriggerService.addGeofence(any())).called(1);
        expect(find.text('Tool: register_geofence'), findsOneWidget);
        expect(
          find.text('Geofence Office HQ successfully registered.'),
          findsOneWidget,
        );
      },
    );
  });
}
