import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_trigger_settings.dart';
import 'package:flutter_ai_agent/domain/tools/chat/battery_optimization_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/exact_alarm_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/app_settings_opener.dart';
import 'package:flutter_ai_agent/presentation/screen/pocket_node/pocket_node_screen.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/utils/permission_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../helpers/mocks.dart';

class _MockPermissionRequester extends Mock implements PermissionRequester {}

class _FakeAppSettingsOpener implements AppSettingsOpener {
  int calls = 0;

  @override
  Future<bool> openAppSettings() async {
    calls++;
    return true;
  }
}

class _MockExactAlarmService extends Mock implements ExactAlarmServiceBase {}

void main() {
  setUpAll(() {
    registerFallbackValue(const AmbientTriggerSettings());
    registerFallbackValue(Permission.notification);
  });

  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
    await sl.reset();
  });

  MockSecureStorageService registerStorage({
    AmbientTriggerSettings settings = const AmbientTriggerSettings(
      geofenceEnabled: false,
      batteryWatchdogEnabled: false,
      notificationListenerEnabled: false,
      heartbeatEnabled: false,
    ),
  }) {
    final mockStorage = MockSecureStorageService();
    when(() => mockStorage.getActiveServerProfile())
        .thenAnswer((_) async => null);
    when(() => mockStorage.getAmbientTriggerSettings())
        .thenAnswer((_) async => settings);
    when(() => mockStorage.saveAmbientTriggerSettings(any()))
        .thenAnswer((_) async {});
    sl.registerSingleton<SecureStorageService>(mockStorage);
    return mockStorage;
  }

  PermissionGate gateWith(
    PermissionStatus status, {
    _FakeAppSettingsOpener? opener,
    PermissionStatus? requestResult,
  }) {
    final requester = _MockPermissionRequester();
    when(() => requester.checkStatus(any())).thenAnswer((_) async => status);
    when(() => requester.requestPermission(any())).thenAnswer(
      (_) async => requestResult ?? status,
    );
    return PermissionGate(requester: requester, settingsOpener: opener);
  }

  Widget createWidgetUnderTest() {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: const PocketNodeScreen(),
    );
  }

  group('PocketNodeScreen POST_NOTIFICATIONS', () {
    testWidgets('granted → no rationale modal and no banner', (tester) async {
      registerStorage();
      sl.registerSingleton<PermissionGate>(
        gateWith(PermissionStatus.granted),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permission_banner_notifications')),
        findsNothing,
      );
      expect(
        find.byKey(const Key('permission_rationale_allow_btn')),
        findsNothing,
      );
    });

    testWidgets(
        'denied → banner with Buka Pengaturan CTA and JIT rationale modal',
        (tester) async {
      registerStorage();
      sl.registerSingleton<PermissionGate>(
        gateWith(PermissionStatus.denied),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permission_rationale_allow_btn')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('permission_rationale_not_now_btn')),
      );
      await tester.pumpAndSettle();

      final banner = find.byKey(const Key('permission_banner_notifications'));
      await tester.scrollUntilVisible(banner, 100.0);
      await tester.pumpAndSettle();

      expect(banner, findsOneWidget);
      expect(find.text('Notifikasi belum aktif'), findsOneWidget);
      expect(
        find.byKey(const Key('action_open_notification_settings')),
        findsOneWidget,
      );
    });

    testWidgets(
        'permanentlyDenied → banner CTA shows Buka Pengaturan modal and settings action is invoked',
        (tester) async {
      registerStorage();
      final opener = _FakeAppSettingsOpener();
      sl.registerSingleton<PermissionGate>(
        gateWith(PermissionStatus.permanentlyDenied, opener: opener),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Dismiss the JIT modal that fired on first build.
      await tester.tap(
        find.byKey(const Key('permission_rationale_not_now_btn')),
      );
      await tester.pumpAndSettle();

      final banner = find.byKey(const Key('permission_banner_notifications'));
      await tester.scrollUntilVisible(banner, 100.0);
      await tester.pumpAndSettle();
      expect(banner, findsOneWidget);

      // Tap the banner CTA → permanently-denied modal with settings action.
      await tester.tap(
        find.byKey(const Key('action_open_notification_settings')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(
          const Key('permission_rationale_permanently_denied_notice'),
        ),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('permission_rationale_allow_btn')),
      );
      await tester.pumpAndSettle();

      expect(opener.calls, 1);
    });

    testWidgets(
        'resume re-check refreshes the banner from granted to denied',
        (tester) async {
      registerStorage();
      var status = PermissionStatus.granted;
      final requester = _MockPermissionRequester();
      when(() => requester.checkStatus(any()))
          .thenAnswer((_) async => status);
      when(() => requester.requestPermission(any()))
          .thenAnswer((_) async => status);
      sl.registerSingleton<PermissionGate>(
        PermissionGate(requester: requester),
      );

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('permission_banner_notifications')),
        findsNothing,
      );

      status = PermissionStatus.denied;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      final banner = find.byKey(const Key('permission_banner_notifications'));
      await tester.scrollUntilVisible(banner, 100.0);
      await tester.pumpAndSettle();
      expect(banner, findsOneWidget);
    });
  });

  group('PocketNodeScreen exact alarm', () {
    testWidgets('canScheduleExactAlarms false → banner + CTA, tap opens settings',
        (tester) async {
      registerStorage();
      final mockExactAlarm = _MockExactAlarmService();
      when(() => mockExactAlarm.canScheduleExactAlarms())
          .thenAnswer((_) async => false);
      when(() => mockExactAlarm.openExactAlarmSettings())
          .thenAnswer((_) async => true);
      sl.registerSingleton<ExactAlarmServiceBase>(mockExactAlarm);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final banner = find.byKey(const Key('permission_banner_exact_alarm'));
      await tester.scrollUntilVisible(banner, 100.0);
      await tester.pumpAndSettle();

      expect(banner, findsOneWidget);
      expect(
        find.text('Alarm presisi belum diizinkan'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('action_open_exact_alarm_settings')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('action_open_exact_alarm_settings')),
      );
      await tester.pumpAndSettle();

      verify(() => mockExactAlarm.openExactAlarmSettings()).called(1);
    });

    testWidgets('canScheduleExactAlarms true → no banner', (tester) async {
      registerStorage();
      final mockExactAlarm = _MockExactAlarmService();
      when(() => mockExactAlarm.canScheduleExactAlarms())
          .thenAnswer((_) async => true);
      sl.registerSingleton<ExactAlarmServiceBase>(mockExactAlarm);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permission_banner_exact_alarm')),
        findsNothing,
      );
    });

    testWidgets(
        'resume re-checks exact alarm status and removes banner after grant',
        (tester) async {
      registerStorage();
      var allowed = false;
      final mockExactAlarm = _MockExactAlarmService();
      when(() => mockExactAlarm.canScheduleExactAlarms())
          .thenAnswer((_) async => allowed);
      sl.registerSingleton<ExactAlarmServiceBase>(mockExactAlarm);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final banner = find.byKey(const Key('permission_banner_exact_alarm'));
      await tester.scrollUntilVisible(banner, 100.0);
      await tester.pumpAndSettle();
      expect(banner, findsOneWidget);

      allowed = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permission_banner_exact_alarm')),
        findsNothing,
      );
    });
  });

  group('PocketNodeScreen notification listener toggle', () {
    testWidgets('granted → toggle enables and persists', (tester) async {
      final mockStorage = registerStorage();
      final mockTriage = MockNotificationTriageService();
      when(() => mockTriage.checkPermission()).thenAnswer((_) async => true);
      when(() => mockTriage.requestPermission())
          .thenAnswer((_) async => true);
      sl.registerSingleton<NotificationTriageServiceBase>(mockTriage);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('switch_notifications')));
      await tester.pumpAndSettle();

      final notifSwitch =
          tester.widget<Switch>(find.byKey(const Key('switch_notifications')));
      expect(notifSwitch.value, isTrue);
      verify(() => mockStorage.saveAmbientTriggerSettings(
            const AmbientTriggerSettings(
              geofenceEnabled: false,
              batteryWatchdogEnabled: false,
              notificationListenerEnabled: true,
              heartbeatEnabled: false,
            ),
          )).called(1);
      verifyNever(() => mockTriage.requestPermission());
    });

    testWidgets(
        'denied → opens listener settings, toggle stays off until resume re-check grants',
        (tester) async {
      final mockStorage = registerStorage();
      final mockTriage = MockNotificationTriageService();
      var granted = false;
      when(() => mockTriage.checkPermission())
          .thenAnswer((_) async => granted);
      when(() => mockTriage.requestPermission())
          .thenAnswer((_) async => true);
      sl.registerSingleton<NotificationTriageServiceBase>(mockTriage);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('switch_notifications')));
      await tester.pumpAndSettle();

      // Optimistic local flag must NOT be set while permission is missing.
      final notifSwitch =
          tester.widget<Switch>(find.byKey(const Key('switch_notifications')));
      expect(notifSwitch.value, isFalse);
      verify(() => mockTriage.requestPermission()).called(1);
      verifyNever(() => mockStorage.saveAmbientTriggerSettings(
            const AmbientTriggerSettings(
              geofenceEnabled: false,
              batteryWatchdogEnabled: false,
              notificationListenerEnabled: true,
              heartbeatEnabled: false,
            ),
          ));

      // User grants access in system settings, then returns.
      granted = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      final notifSwitchAfter = tester
          .widget<Switch>(find.byKey(const Key('switch_notifications')));
      expect(notifSwitchAfter.value, isTrue);
      verify(() => mockStorage.saveAmbientTriggerSettings(
            const AmbientTriggerSettings(
              geofenceEnabled: false,
              batteryWatchdogEnabled: false,
              notificationListenerEnabled: true,
              heartbeatEnabled: false,
            ),
          )).called(1);
    });

    testWidgets(
        'denied and still ungranted after settings → toggle stays off after resume',
        (tester) async {
      final mockStorage = registerStorage();
      final mockTriage = MockNotificationTriageService();
      when(() => mockTriage.checkPermission()).thenAnswer((_) async => false);
      when(() => mockTriage.requestPermission())
          .thenAnswer((_) async => true);
      sl.registerSingleton<NotificationTriageServiceBase>(mockTriage);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Toggle on → routes to settings, toggle stays off.
      await tester.tap(find.byKey(const Key('switch_notifications')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permission_banner_notification_listener')),
        findsNothing,
      );

      // Returns from settings with the listener still ungranted: the real
      // status wins, the toggle must not be stuck optimistically on.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      final notifSwitch = tester
          .widget<Switch>(find.byKey(const Key('switch_notifications')));
      expect(notifSwitch.value, isFalse);
      verify(() => mockTriage.requestPermission()).called(1);
      verifyNever(() => mockStorage.saveAmbientTriggerSettings(
            const AmbientTriggerSettings(
              geofenceEnabled: false,
              batteryWatchdogEnabled: false,
              notificationListenerEnabled: true,
              heartbeatEnabled: false,
            ),
          ));
    });

    testWidgets(
        'listener enabled but ungranted (stale persisted state) → banner with settings CTA',
        (tester) async {
      registerStorage(
        settings: const AmbientTriggerSettings(
          geofenceEnabled: false,
          batteryWatchdogEnabled: false,
          notificationListenerEnabled: true,
          heartbeatEnabled: false,
        ),
      );
      final mockTriage = MockNotificationTriageService();
      when(() => mockTriage.checkPermission()).thenAnswer((_) async => false);
      when(() => mockTriage.requestPermission())
          .thenAnswer((_) async => true);
      sl.registerSingleton<NotificationTriageServiceBase>(mockTriage);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final banner =
          find.byKey(const Key('permission_banner_notification_listener'));
      await tester.scrollUntilVisible(banner, 100.0);
      await tester.pumpAndSettle();

      expect(banner, findsOneWidget);
      expect(
        find.byKey(const Key('action_open_listener_settings')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('action_open_listener_settings')),
      );
      await tester.pumpAndSettle();
      verify(() => mockTriage.requestPermission()).called(1);
    });
  });

  group('PocketNodeScreen battery optimization (existing flow preserved)', () {
    testWidgets(
        'restricted → battery card CTA still present alongside helper banners',
        (tester) async {
      registerStorage();
      final mockBattery = MockBatteryOptimizationService();
      when(() => mockBattery.isBatteryOptimizationDisabled())
          .thenAnswer((_) async => const Right(false));
      when(() => mockBattery.requestDisableBatteryOptimization())
          .thenAnswer((_) async => const Right(true));
      sl.registerSingleton<BatteryOptimizationServiceBase>(mockBattery);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final card = find.byKey(const Key('battery_optimization_card'));
      await tester.scrollUntilVisible(card, 100.0);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('action_disable_battery_opt')),
        findsOneWidget,
      );
    });
  });
}
