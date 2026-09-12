import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/myapp.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_router.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart';
import 'package:flutter_ai_agent/domain/tools/chat/calendar_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/device_context_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/action_approval_sheet.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

void main() {
  late MockFlutterSecureStorage mockSecureStorage;
  late MockLlmRepository mockLlmRepository;
  late MockClipboardService mockClipboardService;
  late MockNotificationService mockNotificationService;
  late Map<String, String> inMemoryStorage;

  setUp(() async {
    await sl.reset();
    inMemoryStorage = {};

    mockSecureStorage = MockFlutterSecureStorage();
    mockLlmRepository = MockLlmRepository();
    mockClipboardService = MockClipboardService();
    mockNotificationService = MockNotificationService();

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

    // Register all dependencies via DI with mock external services
    sl.registerLazySingleton<FlutterSecureStorage>(() => mockSecureStorage);
    sl.registerLazySingleton<SecureStorageService>(
      () => SecureStorageService(storage: mockSecureStorage),
    );
    sl.registerLazySingleton<LlmRepository>(() => mockLlmRepository);
    sl.registerLazySingleton<ClipboardServiceBase>(() => mockClipboardService);
    sl.registerLazySingleton<LocationServiceBase>(() => MockLocationService());
    sl.registerLazySingleton<DeviceContextServiceBase>(
      () => MockDeviceContextService(),
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
    toolRegistry.registerNotificationTools(mockNotificationService);
    sl.registerLazySingleton<ToolRegistry>(() => toolRegistry);

    sl.registerFactory<AgentCubit>(
      () => AgentCubit(
        llmRepository: sl<LlmRepository>(),
        toolRegistry: sl<ToolRegistry>(),
        secureStorageService: sl<SecureStorageService>(),
      ),
    );

    appRouter.go('/splash');
  });

  tearDown(() async {
    await sl.reset();
  });

  group('E2E Agent Integration Tests', () {
    testWidgets(
      'Full ReAct loop: User prompt -> LLM tool call -> Tier 1 Tool execution -> LLM final text response',
      (tester) async {
        // Arrange clipboard service mock
        when(() => mockClipboardService.clipboardRead())
            .thenAnswer((_) async => const Right('Urgent Project Report'));

        // Arrange mock LLM 2-turn stream
        when(() => mockLlmRepository.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
            )).thenAnswer((invocation) async {
          final msgs =
              invocation.namedArguments[#messages] as List<Map<String, dynamic>>;
          if (msgs.length == 1) {
            // Turn 1: LLM decides to call clipboard_read
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_clip_1',
                    name: 'clipboard_read',
                    argumentsFragment: '{}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          } else {
            // Turn 2: LLM generates final answer based on tool result
            return Right(Stream.fromIterable([
              const ChatChunk(
                contentDelta: 'The text currently on your clipboard is: ',
              ),
              const ChatChunk(
                contentDelta: '**Urgent Project Report**',
                finishReason: 'stop',
              ),
            ]));
          }
        });

        // Act: Launch app
        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        // User enters prompt
        await tester.enterText(
          find.byKey(const Key('chat_input_field')),
          'What is on my clipboard?',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('chat_send_button')));

        // Pump frames for stream chunks & async tools
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pumpAndSettle();

        // Assert: Tool executed & rendered in UI
        verify(() => mockClipboardService.clipboardRead()).called(1);
        expect(find.text('What is on my clipboard?'), findsOneWidget);
        expect(find.text('Tool: clipboard_read'), findsOneWidget);
        expect(find.text('Result: clipboard_read'), findsOneWidget);
        expect(find.textContaining('Urgent Project Report'), findsWidgets);
      },
    );

    testWidgets(
      'HITL Gate: User prompt -> Tier 3 Tool -> Approval Sheet -> User Approves -> Tool executes -> LLM final text',
      (tester) async {
        // Arrange notification mock for schedule_reminder
        when(() => mockNotificationService.scheduleReminder(
              title: any(named: 'title'),
              body: any(named: 'body'),
              delayMinutes: any(named: 'delayMinutes'),
            )).thenAnswer((_) async => const Right(null));

        when(() => mockLlmRepository.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
            )).thenAnswer((invocation) async {
          final msgs =
              invocation.namedArguments[#messages] as List<Map<String, dynamic>>;
          if (msgs.length == 1) {
            // Turn 1: LLM calls Tier 3 schedule_reminder
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_remind_1',
                    name: 'schedule_reminder',
                    argumentsFragment:
                        '{"title":"Team Standup","delayMinutes":10}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          } else {
            // Turn 2: After user approval and execution
            return Right(Stream.fromIterable([
              const ChatChunk(
                contentDelta:
                    'I have scheduled your reminder for Team Standup in 10 minutes.',
                finishReason: 'stop',
              ),
            ]));
          }
        });

        // Act: Launch app
        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        // User enters prompt
        await tester.enterText(
          find.byKey(const Key('chat_input_field')),
          'Remind me about team standup in 10 minutes',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('chat_send_button')));

        await tester.pump();
        await tester.pumpAndSettle();

        // HITL sheet must be visible
        expect(find.byType(ActionApprovalSheet), findsOneWidget);
        expect(find.text('schedule_reminder'), findsOneWidget);
        expect(find.textContaining('Team Standup'), findsOneWidget);

        // User taps Approve
        await tester.tap(find.text('Approve'));
        await tester.pumpAndSettle();

        // Verify execution and final message
        verify(() => mockNotificationService.scheduleReminder(
              title: 'Team Standup',
              body: any(named: 'body'),
              delayMinutes: 10,
            )).called(1);

        expect(find.byType(ActionApprovalSheet), findsNothing);
        expect(
          find.text(
            'I have scheduled your reminder for Team Standup in 10 minutes.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'HITL Gate: User prompt -> Tier 3 Tool -> Approval Sheet -> User Rejects -> Rejection to LLM -> LLM final text',
      (tester) async {
        when(() => mockLlmRepository.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
            )).thenAnswer((invocation) async {
          final msgs =
              invocation.namedArguments[#messages] as List<Map<String, dynamic>>;
          if (msgs.length == 1) {
            // Turn 1: LLM calls Tier 3 schedule_reminder
            return Right(Stream.fromIterable([
              const ChatChunk(
                toolCallDeltas: [
                  ToolCallDelta(
                    index: 0,
                    id: 'call_remind_2',
                    name: 'schedule_reminder',
                    argumentsFragment:
                        '{"title":"Delete all data","delayMinutes":1}',
                  ),
                ],
                finishReason: 'tool_calls',
              ),
            ]));
          } else {
            // Turn 2: After user rejection
            return Right(Stream.fromIterable([
              const ChatChunk(
                contentDelta: 'Action cancelled. I did not set the reminder.',
                finishReason: 'stop',
              ),
            ]));
          }
        });

        // Act: Launch app
        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('chat_input_field')),
          'Schedule a critical alert',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('chat_send_button')));

        await tester.pump();
        await tester.pumpAndSettle();

        // HITL sheet must be visible
        expect(find.byType(ActionApprovalSheet), findsOneWidget);

        // User taps Reject
        await tester.tap(find.text('Reject'));
        await tester.pumpAndSettle();

        // Verify tool was NOT executed
        verifyNever(() => mockNotificationService.scheduleReminder(
              title: any(named: 'title'),
              body: any(named: 'body'),
              delayMinutes: any(named: 'delayMinutes'),
            ));

        expect(find.byType(ActionApprovalSheet), findsNothing);
        expect(
          find.text('Action cancelled. I did not set the reminder.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'Settings Propagation: Changes in SettingsScreen propagate to AgentCubit requests',
      (tester) async {
        String? observedBaseUrl;
        String? observedModel;
        String? observedApiKey;

        when(() => mockLlmRepository.streamCompletion(
              baseUrl: any(named: 'baseUrl'),
              model: any(named: 'model'),
              messages: any(named: 'messages'),
              tools: any(named: 'tools'),
              apiKey: any(named: 'apiKey'),
            )).thenAnswer((invocation) async {
          observedBaseUrl = invocation.namedArguments[#baseUrl] as String?;
          observedModel = invocation.namedArguments[#model] as String?;
          observedApiKey = invocation.namedArguments[#apiKey] as String?;

          return Right(Stream.fromIterable([
            const ChatChunk(
              contentDelta: 'Hello from custom endpoint!',
              finishReason: 'stop',
            ),
          ]));
        });

        // Prepopulate storage with custom settings
        inMemoryStorage['llm_base_url'] = 'https://custom.ai/v1';
        inMemoryStorage['llm_model'] = 'claude-3-5-sonnet';
        inMemoryStorage['llm_api_key'] = 'sk-secret-12345';

        // Act: Launch app
        await tester.pumpWidget(const App());
        await tester.pumpAndSettle();

        // Send a message in ChatScreen
        await tester.enterText(
          find.byKey(const Key('chat_input_field')),
          'Hello',
        );
        await tester.pump();
        await tester.tap(find.byKey(const Key('chat_send_button')));

        await tester.pump();
        await tester.pumpAndSettle();

        // Assert: Settings were loaded and passed to LlmRepository
        expect(observedBaseUrl, equals('https://custom.ai/v1'));
        expect(observedModel, equals('claude-3-5-sonnet'));
        expect(observedApiKey, equals('sk-secret-12345'));
        expect(find.text('Hello from custom endpoint!'), findsOneWidget);
      },
    );
  });
}
