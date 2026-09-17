import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_trigger_settings.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/battery_optimization_service.dart';
import 'package:flutter_ai_agent/presentation/screen/pocket_node/pocket_node_screen.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(const AmbientTriggerSettings());
    registerFallbackValue(GatewayPingMessage());
  });

  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
    await sl.reset();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: const PocketNodeScreen(),
    );
  }

  const activeProfile = ServerProfile(
    id: 'p1',
    name: 'Home Server',
    gatewayUrl: 'wss://hermes.example.com/device/ws',
    token: 'tok',
    isActive: true,
  );

  MockSecureStorageService registerStorage(ServerProfile? profile) {
    final mockStorage = MockSecureStorageService();
    when(() => mockStorage.getActiveServerProfile())
        .thenAnswer((_) async => profile);
    sl.registerSingleton<SecureStorageService>(mockStorage);
    return mockStorage;
  }

  String renderedText(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
      .join(' ');

  void expectNoFabricatedEndpointClaims(WidgetTester tester) {
    final joined = renderedText(tester);
    expect(joined.contains('127.0.0.1'), isFalse);
    expect(joined.contains('8644'), isFalse);
    expect(joined.contains('v2.1'), isFalse);
  }

  group('PocketNodeScreen', () {
    testWidgets('renders header with node status and active profile telemetry',
        (tester) async {
      registerStorage(activeProfile);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Pocket Node'), findsOneWidget);
      expect(find.byKey(const Key('node_status_chip')), findsOneWidget);
      expect(find.byKey(const Key('node_rpc_telemetry_card')), findsOneWidget);
      expect(
        find.text('wss://hermes.example.com/device/ws'),
        findsOneWidget,
      );
      expect(find.text('Home Server'), findsOneWidget);
      expectNoFabricatedEndpointClaims(tester);
    });

    testWidgets('never renders the Hermes gateway loopback endpoint',
        (tester) async {
      registerStorage(activeProfile);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expectNoFabricatedEndpointClaims(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await sl.reset();
      registerStorage(null);
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expectNoFabricatedEndpointClaims(tester);
    });

    testWidgets('renders honest empty state when no active profile exists',
        (tester) async {
      registerStorage(null);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('node_no_profile_empty_state')),
        findsOneWidget,
      );
      expect(find.text('No server profile configured'), findsOneWidget);
      expect(
        find.text('Add a server profile to connect this node.'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('action_add_profile')), findsOneWidget);
      expect(find.text('Endpoint'), findsNothing);
      expectNoFabricatedEndpointClaims(tester);
    });

    testWidgets('treats a profile with a blank gateway url as no endpoint',
        (tester) async {
      const blankProfile = ServerProfile(
        id: 'p2',
        name: 'Broken',
        gatewayUrl: '',
        token: 'tok',
        isActive: true,
      );
      registerStorage(blankProfile);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('node_no_profile_empty_state')),
        findsOneWidget,
      );
      expect(find.text('Endpoint'), findsNothing);
      expectNoFabricatedEndpointClaims(tester);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await sl.reset();

      const whitespaceProfile = ServerProfile(
        id: 'p3',
        name: 'Broken',
        gatewayUrl: '   ',
        token: 'tok',
        isActive: true,
      );
      registerStorage(whitespaceProfile);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('node_no_profile_empty_state')),
        findsOneWidget,
      );
      expect(find.text('Endpoint'), findsNothing);
      expectNoFabricatedEndpointClaims(tester);
    });

    testWidgets(
        're-reads the active profile on resume after one is added elsewhere',
        (tester) async {
      ServerProfile? storedProfile;
      final mockStorage = MockSecureStorageService();
      when(() => mockStorage.getActiveServerProfile())
          .thenAnswer((_) async => storedProfile);
      sl.registerSingleton<SecureStorageService>(mockStorage);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('node_no_profile_empty_state')),
        findsOneWidget,
      );

      storedProfile = activeProfile;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('node_no_profile_empty_state')),
        findsNothing,
      );
      expect(
        find.text('wss://hermes.example.com/device/ws'),
        findsOneWidget,
      );
      expectNoFabricatedEndpointClaims(tester);
    });

    testWidgets('status chip shows Standby when gateway is disconnected',
        (tester) async {
      final mockGateway = MockGatewayClient();
      when(() => mockGateway.state)
          .thenReturn(GatewayConnectionState.disconnected);
      when(() => mockGateway.stateStream)
          .thenAnswer((_) => const Stream<GatewayConnectionState>.empty());
      sl.registerSingleton<GatewayClientBase>(mockGateway);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('node_status_chip')),
          matching: find.text('Standby'),
        ),
        findsOneWidget,
      );
      expectNoFabricatedEndpointClaims(tester);
    });

    testWidgets('status chip shows Online when gateway is connected',
        (tester) async {
      final mockGateway = MockGatewayClient();
      when(() => mockGateway.state)
          .thenReturn(GatewayConnectionState.connected);
      when(() => mockGateway.stateStream)
          .thenAnswer((_) => const Stream<GatewayConnectionState>.empty());
      sl.registerSingleton<GatewayClientBase>(mockGateway);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: find.byKey(const Key('node_status_chip')),
          matching: find.text('Online'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('renders ambient trigger switches and toggles state',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(
          find.byKey(const Key('ambient_trigger_geofence')), findsOneWidget);
      expect(find.byKey(const Key('ambient_trigger_battery')), findsOneWidget);
      expect(find.byKey(const Key('ambient_trigger_notifications')),
          findsOneWidget);

      final geofenceSwitch = find.byKey(const Key('switch_geofence'));
      expect(geofenceSwitch, findsOneWidget);

      await tester.tap(geofenceSwitch);
      await tester.pumpAndSettle();
    });

    testWidgets(
        'renders quick action buttons and broadcast ping sends a real heartbeat frame',
        (tester) async {
      final mockGateway = MockGatewayClient();
      when(() => mockGateway.state)
          .thenReturn(GatewayConnectionState.connected);
      when(() => mockGateway.stateStream)
          .thenAnswer((_) => const Stream<GatewayConnectionState>.empty());
      sl.registerSingleton<GatewayClientBase>(mockGateway);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final broadcastButton = find.byKey(const Key('action_broadcast_ping'));
      await tester.scrollUntilVisible(broadcastButton, 100.0);
      await tester.pumpAndSettle();

      expect(broadcastButton, findsOneWidget);
      expect(find.byKey(const Key('action_node_diagnostics')), findsOneWidget);
      expect(find.byKey(const Key('action_flush_events')), findsOneWidget);

      await tester.tap(broadcastButton);
      await tester.pumpAndSettle();

      verify(() => mockGateway.send(any(that: isA<GatewayPingMessage>())))
          .called(1);
      expect(
        find.text('Heartbeat ping sent to the active gateway.'),
        findsOneWidget,
      );
    });

    testWidgets('broadcast ping reports no active gateway when disconnected',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final broadcastButton = find.byKey(const Key('action_broadcast_ping'));
      await tester.scrollUntilVisible(broadcastButton, 100.0);
      await tester.pumpAndSettle();

      await tester.tap(broadcastButton);
      await tester.pumpAndSettle();

      expect(find.text('No active gateway connection.'), findsOneWidget);
    });

    testWidgets(
        'loads persisted ambient trigger settings on init and updates switches',
        (tester) async {
      final mockStorage = MockSecureStorageService();
      when(() => mockStorage.getActiveServerProfile())
          .thenAnswer((_) async => null);
      when(() => mockStorage.getAmbientTriggerSettings()).thenAnswer(
        (_) async => const AmbientTriggerSettings(
          geofenceEnabled: false,
          batteryWatchdogEnabled: false,
          notificationListenerEnabled: true,
          heartbeatEnabled: false,
        ),
      );
      sl.registerSingleton<SecureStorageService>(mockStorage);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final geofenceSwitch =
          tester.widget<Switch>(find.byKey(const Key('switch_geofence')));
      final batterySwitch =
          tester.widget<Switch>(find.byKey(const Key('switch_battery')));
      final notifSwitch =
          tester.widget<Switch>(find.byKey(const Key('switch_notifications')));
      final heartbeatSwitch =
          tester.widget<Switch>(find.byKey(const Key('switch_heartbeat')));

      expect(geofenceSwitch.value, isFalse);
      expect(batterySwitch.value, isFalse);
      expect(notifSwitch.value, isTrue);
      expect(heartbeatSwitch.value, isFalse);
    });

    testWidgets(
        'toggling ambient trigger saves to SecureStorageService and triggers schedulePeriodicCheck / cancelPeriodicCheck on AmbientTriggerServiceBase',
        (tester) async {
      final mockStorage = MockSecureStorageService();
      final mockAmbient = MockAmbientTriggerService();

      when(() => mockStorage.getActiveServerProfile())
          .thenAnswer((_) async => null);
      when(() => mockStorage.getAmbientTriggerSettings()).thenAnswer(
        (_) async => const AmbientTriggerSettings(
          geofenceEnabled: true,
          batteryWatchdogEnabled: true,
          notificationListenerEnabled: true,
          heartbeatEnabled: true,
        ),
      );
      when(() => mockStorage.saveAmbientTriggerSettings(any()))
          .thenAnswer((_) async {});
      when(() => mockAmbient.schedulePeriodicCheck(
            frequency: any(named: 'frequency'),
          )).thenAnswer((_) async => const Right(null));
      when(() => mockAmbient.cancelPeriodicCheck())
          .thenAnswer((_) async => const Right(null));
      when(() => mockAmbient.regions).thenAnswer((_) => const []);

      sl.registerSingleton<SecureStorageService>(mockStorage);
      sl.registerSingleton<AmbientTriggerServiceBase>(mockAmbient);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('switch_geofence')));
      await tester.pumpAndSettle();

      verify(() => mockStorage.saveAmbientTriggerSettings(
            const AmbientTriggerSettings(
              geofenceEnabled: false,
              batteryWatchdogEnabled: true,
              notificationListenerEnabled: true,
              heartbeatEnabled: true,
            ),
          )).called(1);
      verify(() => mockAmbient.schedulePeriodicCheck()).called(1);

      await tester.tap(find.byKey(const Key('switch_battery')));
      await tester.pumpAndSettle();

      verify(() => mockStorage.saveAmbientTriggerSettings(
            const AmbientTriggerSettings(
              geofenceEnabled: false,
              batteryWatchdogEnabled: false,
              notificationListenerEnabled: true,
              heartbeatEnabled: true,
            ),
          )).called(1);
      verify(() => mockAmbient.cancelPeriodicCheck()).called(1);
    });

    testWidgets(
        'renders battery optimization card when exempt (shows status chip Unrestricted)',
        (tester) async {
      final mockBattery = MockBatteryOptimizationService();
      when(() => mockBattery.isBatteryOptimizationDisabled())
          .thenAnswer((_) async => const Right(true));
      sl.registerSingleton<BatteryOptimizationServiceBase>(mockBattery);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final cardFinder = find.byKey(const Key('battery_optimization_card'));
      await tester.scrollUntilVisible(cardFinder, 100.0);
      await tester.pumpAndSettle();

      expect(cardFinder, findsOneWidget);
      expect(find.text('Battery Optimization'), findsOneWidget);
      expect(
        find.text('Background execution unrestricted by Android Doze'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('battery_opt_status_exempt')), findsOneWidget);
      expect(find.text('Unrestricted'), findsOneWidget);
      expect(find.byKey(const Key('action_disable_battery_opt')), findsNothing);
    });

    testWidgets(
        'renders battery optimization card when restricted, shows Disable Optimization button, and tapping it calls requestDisableBatteryOptimization and shows feedback snackbar',
        (tester) async {
      final mockBattery = MockBatteryOptimizationService();
      var isExempt = false;
      when(() => mockBattery.isBatteryOptimizationDisabled())
          .thenAnswer((_) async => Right(isExempt));
      when(() => mockBattery.requestDisableBatteryOptimization())
          .thenAnswer((_) async {
        isExempt = true;
        return const Right(true);
      });
      sl.registerSingleton<BatteryOptimizationServiceBase>(mockBattery);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final cardFinder = find.byKey(const Key('battery_optimization_card'));
      await tester.scrollUntilVisible(cardFinder, 100.0);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('battery_opt_status_restricted')),
        findsOneWidget,
      );
      expect(find.text('Optimized (Restricted)'), findsOneWidget);
      expect(
        find.text(
          'Background ambient triggers may be throttled by Android Doze',
        ),
        findsOneWidget,
      );

      final disableButton = find.byKey(const Key('action_disable_battery_opt'));
      expect(disableButton, findsOneWidget);

      await tester.tap(disableButton);
      await tester.pumpAndSettle();

      verify(() => mockBattery.requestDisableBatteryOptimization()).called(1);
      verify(() => mockBattery.isBatteryOptimizationDisabled()).called(2);
      expect(
        find.text('Battery optimization exemption requested.'),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('battery_opt_status_exempt')),
        findsOneWidget,
      );
    });

    testWidgets(
        'diagnostics button accounts for BatteryOptimizationServiceBase and AmbientTriggerServiceBase',
        (tester) async {
      final mockBattery = MockBatteryOptimizationService();
      final mockAmbient = MockAmbientTriggerService();
      when(() => mockBattery.isBatteryOptimizationDisabled())
          .thenAnswer((_) async => const Right(false));
      when(() => mockAmbient.regions).thenAnswer((_) => const []);

      var expectedOperationalServices = 0;
      sl.registerSingleton<BatteryOptimizationServiceBase>(mockBattery);
      expectedOperationalServices++;
      sl.registerSingleton<AmbientTriggerServiceBase>(mockAmbient);
      expectedOperationalServices++;

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final diagnosticsButton =
          find.byKey(const Key('action_node_diagnostics'));
      await tester.scrollUntilVisible(diagnosticsButton, 100.0);
      await tester.pumpAndSettle();

      await tester.tap(diagnosticsButton);
      await tester.pumpAndSettle();

      expect(
        find.textContaining(
          'Self diagnostics complete: $expectedOperationalServices services operational.',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
        're-checks battery optimization status when app resumes from background',
        (tester) async {
      final mockBattery = MockBatteryOptimizationService();
      var isExempt = false;
      when(() => mockBattery.isBatteryOptimizationDisabled())
          .thenAnswer((_) async => Right(isExempt));

      sl.registerSingleton<BatteryOptimizationServiceBase>(mockBattery);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final cardFinder = find.byKey(const Key('battery_optimization_card'));
      await tester.scrollUntilVisible(cardFinder, 100.0);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('battery_opt_status_restricted')), findsOneWidget);

      // Simulate user returning from Android settings
      isExempt = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      verify(() => mockBattery.isBatteryOptimizationDisabled()).called(2);
      expect(find.byKey(const Key('battery_opt_status_exempt')), findsOneWidget);
    });

    testWidgets('renders geofence empty state when no geofences are registered',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('geofence_empty_state')), findsOneWidget);
      expect(find.text('No active geofences.'), findsOneWidget);
    });
  });
}
