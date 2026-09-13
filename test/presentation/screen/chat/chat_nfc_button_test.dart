import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/chat_chunk.dart';
import 'package:flutter_ai_agent/domain/entities/chat/nfc_tag_prompt_binding.dart';
import 'package:flutter_ai_agent/domain/repositories/chat/llm_repository.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';
import 'package:flutter_ai_agent/presentation/navigation/app_routes.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/settings_screen.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class _FakeNfcService extends Mock implements NfcServiceBase {}

class _FakeSecureStorageService extends Mock implements SecureStorageService {}

class _MockLlmRepository extends Mock implements LlmRepository {}

void main() {
  late _FakeNfcService fakeNfc;
  late _FakeSecureStorageService fakeStorage;
  late _MockLlmRepository mockLlm;
  late AgentCubit cubit;

  setUpAll(() {
    registerFallbackValue(<Map<String, dynamic>>[]);
    registerFallbackValue('');
    registerFallbackValue(0.7);
  });

  setUp(() async {
    await sl.reset();
    fakeNfc = _FakeNfcService();
    fakeStorage = _FakeSecureStorageService();
    mockLlm = _MockLlmRepository();
    cubit = AgentCubit(
      llmRepository: mockLlm,
      nfcService: fakeNfc,
      secureStorageService: fakeStorage,
    );

    when(() => fakeStorage.getSettings())
        .thenAnswer((_) async => const SettingsData());
    when(() => fakeStorage.getNfcPromptBindings())
        .thenAnswer((_) async => const []);
    when(() => fakeNfc.isAvailable())
        .thenAnswer((_) async => const Right(true));
    when(() => fakeNfc.isEnabled())
        .thenAnswer((_) async => const Right(true));
  });

  tearDown(() async {
    await cubit.close();
    await sl.reset();
  });

  Widget createWidgetUnderTest() {
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          name: AppRoutes.nrChat,
          builder: (context, state) => ChatScreen(agentCubit: cubit),
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

  void stubLlmIdleStream() {
    when(() => mockLlm.streamCompletion(
          baseUrl: any(named: 'baseUrl'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          apiKey: any(named: 'apiKey'),
          temperature: any(named: 'temperature'),
        )).thenAnswer((_) async => Right(const Stream<ChatChunk>.empty()));
  }

  testWidgets('AppBar renders NFC scan and e-Money balance buttons',
      (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('chat_nfc_scan_button')), findsOneWidget);
    expect(find.byKey(const Key('chat_nfc_balance_button')), findsOneWidget);
  });

  testWidgets(
      'tapping scan with no matching binding shows next-action SnackBar with Open Settings action',
      (tester) async {
    when(() => fakeNfc.readCardUid()).thenAnswer(
      (_) async => const Right('aabbcc'),
    );
    when(() => fakeStorage.getNfcPromptBindings()).thenAnswer(
      (_) async => [
        NfcTagPromptBinding(
          cardUid: 'deadbeef',
          prompt: 'Unknown tag prompt',
          createdAt: DateTime(2026),
        ),
      ],
    );

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat_nfc_scan_button')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No prompt bound to this NFC tag'),
      findsOneWidget,
    );
    // The message itself contains the word "Settings", so this finder matches
    // both the message Text and the SnackBarAction label.
    expect(find.textContaining('Settings'), findsNWidgets(2));
    expect(find.text('Open Settings'), findsOneWidget);
    expect(find.byType(SnackBarAction), findsOneWidget);
  });

  testWidgets(
      'tapping scan with a matching binding dispatches the bound prompt as a user message',
      (tester) async {
    stubLlmIdleStream();
    when(() => fakeNfc.readCardUid()).thenAnswer(
      (_) async => const Right('AABBCC'),
    );
    when(() => fakeStorage.getNfcPromptBindings()).thenAnswer(
      (_) async => [
        NfcTagPromptBinding(
          cardUid: 'aabbcc',
          prompt: 'Turn on the lights',
          createdAt: DateTime(2026),
        ),
      ],
    );

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat_nfc_scan_button')));
    await tester.pumpAndSettle();

    expect(find.text('Turn on the lights'), findsOneWidget);
    expect(find.textContaining('No prompt bound to this NFC tag'),
        findsNothing);
  });

  testWidgets(
      'tapping scan when the NFC service returns Left shows the no-binding SnackBar and never dispatches',
      (tester) async {
    when(() => fakeNfc.readCardUid())
        .thenAnswer((_) async => Left(const CacheFailure('NFC unavailable')));

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat_nfc_scan_button')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('No prompt bound to this NFC tag'),
      findsOneWidget,
    );
    expect(cubit.messages, isEmpty);
    verifyNever(() => mockLlm.streamCompletion(
          baseUrl: any(named: 'baseUrl'),
          model: any(named: 'model'),
          messages: any(named: 'messages'),
          tools: any(named: 'tools'),
          apiKey: any(named: 'apiKey'),
          temperature: any(named: 'temperature'),
        ));
  });

  testWidgets(
      'tapping the balance button renders the brand and formatted balance in a SnackBar',
      (tester) async {
    when(() => fakeNfc.readEmoneyBalance()).thenAnswer(
      (_) async => Right(
        EmoneyBalance(
          brand: EmoneyCardBrand.mandiriEmoney,
          cardUid: 'aabbcc',
          balanceRupiah: 25000,
        ),
      ),
    );

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat_nfc_balance_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Mandiri e-Money balance'), findsOneWidget);
    expect(find.textContaining('Rp 25.000'), findsOneWidget);
  });

  testWidgets('double-tap while a scan is in flight only reads the card once',
      (tester) async {
    final gate = Completer<void>();
    when(() => fakeNfc.readCardUid()).thenAnswer((_) async {
      await gate.future;
      return const Right('aabbcc');
    });

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('chat_nfc_scan_button')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('chat_nfc_scan_button')));
    await tester.pump();

    verify(() => fakeNfc.readCardUid()).called(1);

    gate.complete();
    await tester.pumpAndSettle();
  });

  group('AgentCubit NFC pre-flight checks and DI', () {
    test('scanNfcAndDispatchPrompt returns false when NFC is not available',
        () async {
      when(() => fakeNfc.isAvailable())
          .thenAnswer((_) async => const Right(false));

      final result = await cubit.scanNfcAndDispatchPrompt();

      expect(result, isFalse);
      verifyNever(() => fakeNfc.readCardUid());
    });

    test('scanNfcAndDispatchPrompt returns false when NFC is disabled', () async {
      when(() => fakeNfc.isAvailable())
          .thenAnswer((_) async => const Right(true));
      when(() => fakeNfc.isEnabled())
          .thenAnswer((_) async => const Right(false));

      final result = await cubit.scanNfcAndDispatchPrompt();

      expect(result, isFalse);
      verifyNever(() => fakeNfc.readCardUid());
    });

    test('scanNfcEmoneyBalance returns null when NFC is not available', () async {
      when(() => fakeNfc.isAvailable())
          .thenAnswer((_) async => const Right(false));

      final result = await cubit.scanNfcEmoneyBalance();

      expect(result, isNull);
      verifyNever(() => fakeNfc.readEmoneyBalance());
    });

    test('scanNfcEmoneyBalance returns null when NFC is disabled', () async {
      when(() => fakeNfc.isAvailable())
          .thenAnswer((_) async => const Right(true));
      when(() => fakeNfc.isEnabled())
          .thenAnswer((_) async => const Right(false));

      final result = await cubit.scanNfcEmoneyBalance();

      expect(result, isNull);
      verifyNever(() => fakeNfc.readEmoneyBalance());
    });

    test('AgentCubit.create factory wires custom storage and nfcService', () {
      final createdCubit = AgentCubit.create(
        llmRepository: mockLlm,
        secureStorageService: fakeStorage,
        nfcService: fakeNfc,
      );

      expect(createdCubit, isNotNull);
      createdCubit.close();
    });
  });
}
