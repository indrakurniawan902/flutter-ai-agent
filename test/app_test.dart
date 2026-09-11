import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/app.dart';
import 'package:flutter_ai_agent/core/di/injection_container.dart';
import 'package:flutter_ai_agent/features/settings/data/secure_storage_service.dart';
import 'package:flutter_ai_agent/features/splash/presentation/screens/splash_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'helpers/mocks.dart';

void main() {
  late MockSecureStorageService mockStorageService;

  setUp(() async {
    await sl.reset();
    mockStorageService = MockSecureStorageService();
    when(() => mockStorageService.getBaseUrl())
        .thenAnswer((_) async => 'https://indra-9router.my.id/v1');
    when(() => mockStorageService.getApiKey())
        .thenAnswer((_) async => 'sk-test');
    when(() => mockStorageService.getModel())
        .thenAnswer((_) async => 'ag-glm');
    when(() => mockStorageService.getTemperature())
        .thenAnswer((_) async => 0.7);

    await initDependencies();

    if (sl.isRegistered<SecureStorageService>()) {
      await sl.unregister<SecureStorageService>();
    }
    sl.registerLazySingleton<SecureStorageService>(() => mockStorageService);
  });

  tearDown(() async {
    await sl.reset();
  });

  testWidgets('App renders with dark theme and splash screen transitioning to Chat', (tester) async {
    await tester.pumpWidget(const App());

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme?.brightness, Brightness.dark);
    expect(find.byType(SplashScreen), findsOneWidget);

    // Fast-forward past splash duration and transition to ChatScreen
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    expect(find.text('Flames'), findsOneWidget);
    expect(find.byKey(const Key('chat_settings_button')), findsOneWidget);
  });

  testWidgets('App navigates from Chat to SettingsScreen on settings button tap', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();

    final settingsButton = find.byKey(const Key('chat_settings_button'));
    await tester.tap(settingsButton);
    await tester.pumpAndSettle();

    expect(find.text('LLM Settings'), findsOneWidget);
    expect(find.byKey(const Key('settings_base_url_field')), findsOneWidget);
    expect(find.byKey(const Key('settings_save_button')), findsOneWidget);
  });

  testWidgets('App switches tabs via FloatingBottomNavBar', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('floating_bottom_nav_bar')), findsOneWidget);
    expect(find.text('Flames'), findsOneWidget);

    // Tap Skills tab
    await tester.tap(find.byKey(const Key('nav_item_skills')));
    await tester.pumpAndSettle();
    expect(find.text('Skills Hub'), findsOneWidget);

    // Tap Pocket Node tab
    await tester.tap(find.byKey(const Key('nav_item_node')));
    await tester.pumpAndSettle();
    expect(find.text('Pocket Node'), findsOneWidget);

    // Tap Memory Vault tab
    await tester.tap(find.byKey(const Key('nav_item_vault')));
    await tester.pumpAndSettle();
    expect(find.text('Memory Vault'), findsOneWidget);

    // Tap Settings tab
    await tester.tap(find.byKey(const Key('nav_item_settings')));
    await tester.pumpAndSettle();
    expect(find.text('LLM Settings'), findsOneWidget);
  });
}
