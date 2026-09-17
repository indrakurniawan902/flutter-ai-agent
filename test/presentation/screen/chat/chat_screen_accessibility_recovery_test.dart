import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_message.dart';
import 'package:flutter_ai_agent/domain/tools/chat/accessibility_inspector_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/intent_launcher_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/system_settings_allow_list.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/settings_screen.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_routes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

class MockIntentLauncherService extends Mock
    implements IntentLauncherServiceBase {}

void main() {
  late MockAgentCubit mockAgentCubit;
  late MockSettingsCubit mockSettingsCubit;
  late MockAccessibilityInspectorService mockAccessibilityService;
  late MockIntentLauncherService mockIntentLauncher;
  late StreamController<AgentState> stateController;

  setUp(() async {
    await sl.reset();
    mockAgentCubit = MockAgentCubit();
    mockSettingsCubit = MockSettingsCubit();
    mockAccessibilityService = MockAccessibilityInspectorService();
    mockIntentLauncher = MockIntentLauncherService();
    stateController = StreamController<AgentState>.broadcast();

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.sessions).thenReturn(const []);
    when(() => mockAgentCubit.activeSessionId).thenReturn(null);
    when(() => mockAgentCubit.activeSessionTitle).thenReturn('New chat');
    when(() => mockAgentCubit.refreshSessions()).thenAnswer((_) async {});
    when(() => mockAgentCubit.newChat()).thenAnswer((_) async {});
    when(() => mockAgentCubit.switchSession(any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.renameSession(any(), any()))
        .thenAnswer((_) async {});
    when(() => mockAgentCubit.deleteSession(any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.messages).thenReturn([]);
    when(() => mockAgentCubit.stream).thenAnswer((_) => stateController.stream);
    when(() => mockAgentCubit.stop()).thenAnswer((_) async {});

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsLoaded(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o',
        temperature: 0.7,
      ),
    );
    when(() => mockSettingsCubit.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockIntentLauncher.launchSystemSetting(any()))
        .thenAnswer((_) async => const Right('ok'));

    sl.registerFactory<AgentCubit>(() => mockAgentCubit);
    sl.registerFactory<SettingsCubit>(() => mockSettingsCubit);
    sl.registerLazySingleton<AccessibilityInspectorServiceBase>(
      () => mockAccessibilityService,
    );
    sl.registerLazySingleton<IntentLauncherServiceBase>(
      () => mockIntentLauncher,
    );
  });

  tearDown(() async {
    await stateController.close();
    await sl.reset();
  });

  Widget createWidgetUnderTest() {
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          name: AppRoutes.nrChat,
          builder: (context, state) => const ChatScreen(),
        ),
        GoRoute(
          path: '/settings',
          name: AppRoutes.nrSettings,
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    );

    return MaterialApp.router(
      theme: AppTheme.darkTheme,
      routerConfig: router,
    );
  }

  group('ChatScreen - Screen Reader Recovery', () {
    testWidgets(
        'renders screen_reader_warning_banner when the service reports notEnabled '
        'and the enable button opens the accessibility settings page',
        (tester) async {
      when(() => mockAccessibilityService.checkStatus())
          .thenAnswer((_) async => AccessibilityStatus.notEnabled);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('screen_reader_warning_banner')),
        findsOneWidget,
      );
      expect(find.text('Screen Reader Belum Aktif'), findsOneWidget);
      expect(
        find.text(
          'Agen tidak bisa membaca layar tanpa layanan Flames Screen Reader.',
        ),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('screen_reader_banner_enable_button')),
      );
      await tester.pumpAndSettle();

      verify(
        () => mockIntentLauncher.launchSystemSetting(
          SystemSettingsAllowList.accessibility,
        ),
      ).called(1);
    });

    testWidgets('tapping dismiss button hides the screen reader banner',
        (tester) async {
      when(() => mockAccessibilityService.checkStatus())
          .thenAnswer((_) async => AccessibilityStatus.notEnabled);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('screen_reader_warning_banner')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('screen_reader_banner_dismiss_button')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('screen_reader_warning_banner')),
        findsNothing,
      );
    });

    testWidgets(
        'renders tool_result_accessibility_button for an accessibility tool result '
        'and tapping it opens the accessibility settings page',
        (tester) async {
      when(() => mockAccessibilityService.checkStatus())
          .thenAnswer((_) async => AccessibilityStatus.active);
      when(() => mockAgentCubit.messages).thenReturn([
        ChatMessage(
          role: 'tool',
          name: 'launch_system_setting',
          content: AccessibilityMessages.forStatus(
            AccessibilityStatus.notEnabled,
          ),
        ),
      ]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(
        find.text('Permission Required: launch_system_setting'),
      );
      await tester.pumpAndSettle();

      final button =
          find.byKey(const Key('tool_result_accessibility_button'));
      expect(button, findsOneWidget);
      expect(find.text('Aktifkan Screen Reader'), findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      verify(
        () => mockIntentLauncher.launchSystemSetting(
          SystemSettingsAllowList.accessibility,
        ),
      ).called(1);
    });

    testWidgets(
        'does not render tool_result_accessibility_button for a generic '
        'permission failure', (tester) async {
      when(() => mockAccessibilityService.checkStatus())
          .thenAnswer((_) async => AccessibilityStatus.active);
      when(() => mockAgentCubit.messages).thenReturn([
        const ChatMessage(
          role: 'tool',
          name: 'get_location',
          content: 'Error: Permission not granted for get_location',
        ),
      ]);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Permission Required: get_location'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('tool_result_accessibility_button')),
        findsNothing,
      );
    });

    testWidgets(
        'a resumed lifecycle event re-checks the screen reader and clears the '
        'dismissal once the service is active', (tester) async {
      when(() => mockAccessibilityService.checkStatus())
          .thenAnswer((_) async => AccessibilityStatus.notEnabled);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('screen_reader_banner_dismiss_button')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('screen_reader_warning_banner')),
        findsNothing,
      );

      clearInteractions(mockAccessibilityService);
      when(() => mockAccessibilityService.checkStatus())
          .thenAnswer((_) async => AccessibilityStatus.active);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      verify(() => mockAccessibilityService.checkStatus()).called(1);
      expect(
        find.byKey(const Key('screen_reader_warning_banner')),
        findsNothing,
      );

      when(() => mockAccessibilityService.checkStatus())
          .thenAnswer((_) async => AccessibilityStatus.notEnabled);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('screen_reader_warning_banner')),
        findsOneWidget,
      );
    });
  });
}
