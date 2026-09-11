import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/app.dart';
import 'package:flutter_ai_agent/core/di/injection_container.dart';
import 'package:flutter_ai_agent/features/settings/data/secure_storage_service.dart';
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

  testWidgets('App renders with dark theme', (tester) async {
    await tester.pumpWidget(const App());

    final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(materialApp.theme?.brightness, Brightness.dark);
    expect(find.text('AI Agent'), findsOneWidget);
    expect(find.byKey(const Key('chat_settings_button')), findsOneWidget);
  });

  testWidgets('App navigates from Chat to SettingsScreen on settings button tap', (tester) async {
    await tester.pumpWidget(const App());
    await tester.pump();

    final settingsButton = find.byKey(const Key('chat_settings_button'));
    await tester.tap(settingsButton);
    await tester.pumpAndSettle();

    expect(find.text('LLM Settings'), findsOneWidget);
    expect(find.byKey(const Key('settings_base_url_field')), findsOneWidget);
    expect(find.byKey(const Key('settings_save_button')), findsOneWidget);
  });
}
