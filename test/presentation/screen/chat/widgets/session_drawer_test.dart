import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/chat/session.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/session_drawer.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/settings_screen.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_routes.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

Session _session(int id, String title, {int? updatedAt}) {
  final ts = updatedAt ?? DateTime(2026, 9, 1).millisecondsSinceEpoch;
  return Session(
    id: id,
    profileId: 'p1',
    title: title,
    createdAt: ts,
    updatedAt: ts,
  );
}

void main() {
  late MockAgentCubit mockAgentCubit;
  late MockSettingsCubit mockSettingsCubit;
  late StreamController<AgentState> stateController;
  late List<Session> sessions;
  late int? activeId;

  setUp(() async {
    await sl.reset();
    mockAgentCubit = MockAgentCubit();
    mockSettingsCubit = MockSettingsCubit();
    stateController = StreamController<AgentState>.broadcast();
    sessions = <Session>[];
    activeId = null;

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.messages).thenReturn([]);
    when(() => mockAgentCubit.stream).thenAnswer((_) => stateController.stream);
    when(() => mockAgentCubit.stop()).thenAnswer((_) async {});
    when(() => mockAgentCubit.sessions).thenAnswer((_) => sessions);
    when(() => mockAgentCubit.activeSessionId)
        .thenAnswer((_) => activeId);
    when(() => mockAgentCubit.activeSessionTitle).thenReturn('New chat');
    when(() => mockAgentCubit.refreshSessions()).thenAnswer((_) async {});
    when(() => mockAgentCubit.newChat()).thenAnswer((_) async {});
    when(() => mockAgentCubit.switchSession(any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.renameSession(any(), any()))
        .thenAnswer((_) async {});
    when(() => mockAgentCubit.deleteSession(any())).thenAnswer((_) async {});

    when(() => mockSettingsCubit.state).thenReturn(
      const SettingsLoaded(
        baseUrl: 'https://api.openai.com/v1',
        apiKey: 'test-key',
        model: 'gpt-4o',
        temperature: 0.7,
      ),
    );
    when(() => mockSettingsCubit.stream).thenAnswer(
      (_) => const Stream<SettingsState>.empty(),
    );

    sl.registerFactory<AgentCubit>(() => mockAgentCubit);
    sl.registerFactory<SettingsCubit>(() => mockSettingsCubit);
  });

  tearDown(() async {
    await stateController.close();
    await sl.reset();
  });

  Widget wrapDrawer(Widget child) {
    return BlocProvider<AgentCubit>.value(
      value: mockAgentCubit,
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        home: Scaffold(body: child),
      ),
    );
  }

  group('SessionDrawer', () {
    testWidgets('renders empty label when no sessions', (tester) async {
      await tester.pumpWidget(wrapDrawer(const SessionDrawer()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('session_empty_label')), findsOneWidget);
      expect(find.text('No chats yet'), findsOneWidget);
    });

    testWidgets('lists sessions and marks active one', (tester) async {
      sessions = [
        _session(1, 'Alpha'),
        _session(2, 'Beta'),
      ];
      activeId = 2;
      await tester.pumpWidget(wrapDrawer(const SessionDrawer()));
      await tester.pumpAndSettle();
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      // Active tile has a teal left border.
      final containers = find.byType(Container);
      var foundActiveBorder = false;
      for (final el in tester.widgetList<Container>(containers)) {
        final dec = el.decoration;
        if (dec is BoxDecoration &&
            dec.border is Border &&
            (dec.border as Border).left.color == const Color(0xFF008080)) {
          foundActiveBorder = true;
          break;
        }
      }
      expect(foundActiveBorder, isTrue, reason: 'active border missing');
    });

    testWidgets('New Chat button calls newChat()', (tester) async {
      await tester.pumpWidget(wrapDrawer(const SessionDrawer()));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session_new_chat_button')));
      await tester.pumpAndSettle();
      verify(() => mockAgentCubit.newChat()).called(1);
    });

    testWidgets('tapping item calls switchSession(id)', (tester) async {
      sessions = [_session(7, 'Work')];
      await tester.pumpWidget(wrapDrawer(const SessionDrawer()));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Work'));
      await tester.pumpAndSettle();
      verify(() => mockAgentCubit.switchSession(7)).called(1);
    });

    testWidgets('long press opens rename dialog; save calls renameSession',
        (tester) async {
      sessions = [_session(3, 'Old title')];
      await tester.pumpWidget(wrapDrawer(const SessionDrawer()));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('Old title'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('session_rename_field')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('session_rename_field')),
        'New title',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session_rename_save_button')));
      await tester.pumpAndSettle();
      verify(
        () => mockAgentCubit.renameSession(3, 'New title'),
      ).called(1);
    });

    testWidgets('swipe delete shows confirm dialog; confirm calls deleteSession',
        (tester) async {
      sessions = [_session(9, 'Doomed')];
      await tester.pumpWidget(wrapDrawer(const SessionDrawer()));
      await tester.pumpAndSettle();
      await tester.drag(
        find.text('Doomed'),
        const Offset(-400, 0),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('session_delete_confirm_button')),
          findsOneWidget);
      await tester.tap(find.byKey(const Key('session_delete_confirm_button')));
      await tester.pumpAndSettle();
      verify(() => mockAgentCubit.deleteSession(9)).called(1);
    });

    testWidgets('cancel dialog dismisses without calling deleteSession',
        (tester) async {
      sessions = [_session(9, 'Keep')];
      await tester.pumpWidget(wrapDrawer(const SessionDrawer()));
      await tester.pumpAndSettle();
      await tester.drag(find.text('Keep'), const Offset(-400, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('session_cancel_delete_button')));
      await tester.pumpAndSettle();
      verifyNever(() => mockAgentCubit.deleteSession(any()));
    });

    testWidgets('refreshSessions called on first frame', (tester) async {
      await tester.pumpWidget(wrapDrawer(const SessionDrawer()));
      await tester.pumpAndSettle();
      verify(() => mockAgentCubit.refreshSessions()).called(1);
    });
  });

  group('ChatScreen drawer wiring', () {
    Widget createChatScreen() {
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

    testWidgets('leading button opens drawer', (tester) async {
      sessions = [_session(11, 'Sidebar')];
      await tester.pumpWidget(createChatScreen());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat_sessions_button')), findsOneWidget);
      expect(find.text('· New chat'), findsOneWidget);
      await tester.tap(find.byKey(const Key('chat_sessions_button')));
      await tester.pumpAndSettle();
      expect(find.text('Sidebar'), findsOneWidget);
      expect(find.byKey(const Key('session_new_chat_button')), findsOneWidget);
    });
  });
}
