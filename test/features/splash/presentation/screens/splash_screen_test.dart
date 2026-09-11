import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/di/injection_container.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/features/chat/presentation/screens/chat_screen.dart';
import 'package:flutter_ai_agent/features/settings/data/secure_storage_service.dart';
import 'package:flutter_ai_agent/features/splash/presentation/screens/splash_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

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

  Widget buildTestWidget({
    Duration duration = const Duration(milliseconds: 2500),
    Widget? nextScreen,
    VoidCallback? onComplete,
  }) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: SplashScreen(
        duration: duration,
        nextScreen: nextScreen,
        onComplete: onComplete,
      ),
    );
  }

  group('SplashScreen - UI & Rendering', () {
    testWidgets('renders dark background, splash image, title and subtitle',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        duration: const Duration(seconds: 10),
      ));

      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, HermesColors.stage);

      expect(find.byKey(const Key('splash_gif_image')), findsOneWidget);
      expect(find.byKey(const Key('splash_app_title')), findsOneWidget);
      expect(find.text('FLAMES'), findsOneWidget);
      expect(find.byKey(const Key('splash_app_subtitle')), findsOneWidget);
      expect(find.text('Autonomous Device Workstation'), findsOneWidget);
    });
  });

  group('SplashScreen - Navigation & Lifecycle', () {
    testWidgets(
        'automatically navigates to provided nextScreen after timer duration',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        duration: const Duration(milliseconds: 2000),
        nextScreen: const Scaffold(
          body: Center(child: Text('Next Destination Screen')),
        ),
      ));

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('Next Destination Screen'), findsNothing);

      // Advance clock past timer and complete transition animation
      await tester.pump(const Duration(milliseconds: 2000));
      await tester.pumpAndSettle();

      expect(find.byType(SplashScreen), findsNothing);
      expect(find.text('Next Destination Screen'), findsOneWidget);
    });

    testWidgets('automatically navigates to ChatScreen by default after timer duration',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        duration: const Duration(milliseconds: 1500),
      ));

      expect(find.byType(SplashScreen), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1500));
      await tester.pumpAndSettle();

      expect(find.byType(ChatScreen), findsOneWidget);
      expect(find.byKey(const Key('chat_settings_button')), findsOneWidget);
      expect(find.byKey(const Key('chat_app_bar_logo')), findsOneWidget);
    });

    testWidgets('navigates immediately when user taps on splash screen',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        duration: const Duration(seconds: 30),
        nextScreen: const Scaffold(
          body: Center(child: Text('Tapped Immediate Target')),
        ),
      ));

      expect(find.byType(SplashScreen), findsOneWidget);
      expect(find.text('Tapped Immediate Target'), findsNothing);

      await tester.tap(find.byType(SplashScreen));
      await tester.pumpAndSettle();

      expect(find.byType(SplashScreen), findsNothing);
      expect(find.text('Tapped Immediate Target'), findsOneWidget);
    });

    testWidgets('invokes onComplete callback when navigation occurs',
        (tester) async {
      var completed = false;

      await tester.pumpWidget(buildTestWidget(
        duration: const Duration(milliseconds: 500),
        nextScreen: const Scaffold(body: Text('Done')),
        onComplete: () {
          completed = true;
        },
      ));

      expect(completed, isFalse);

      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(completed, isTrue);
    });

    testWidgets('cancels timer safely when disposed before completion',
        (tester) async {
      await tester.pumpWidget(buildTestWidget(
        duration: const Duration(seconds: 10),
      ));

      expect(find.byType(SplashScreen), findsOneWidget);

      // Replace widget tree before timer fires
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('Replaced'))));
      await tester.pumpAndSettle();

      expect(find.byType(SplashScreen), findsNothing);
      expect(find.text('Replaced'), findsOneWidget);
    });
  });
}
