import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_ai_agent/features/chat/data/models/ambient_event.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/tool_registry.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late AmbientTriggerService service;
  late MockBatteryPlatformWrapper mockBattery;
  late MockLocationService mockLocationService;
  late MockNotificationService mockNotificationService;
  late MockWorkmanagerPlatformWrapper mockWorkmanager;
  late StreamController<BatteryState> batteryStateController;

  const sampleRegionOffice = GeofenceRegion(
    id: 'office_1',
    name: 'HQ Office',
    latitude: -6.200000,
    longitude: 106.816666,
    radiusMeters: 200.0,
    triggerOnEnter: true,
    triggerOnExit: true,
  );

  const sampleRegionHome = GeofenceRegion(
    id: 'home_1',
    name: 'Home',
    latitude: -6.300000,
    longitude: 106.900000,
    radiusMeters: 150.0,
    triggerOnEnter: true,
    triggerOnExit: false,
  );

  setUp(() {
    mockBattery = MockBatteryPlatformWrapper();
    mockLocationService = MockLocationService();
    mockNotificationService = MockNotificationService();
    mockWorkmanager = MockWorkmanagerPlatformWrapper();
    batteryStateController = StreamController<BatteryState>.broadcast();

    when(() => mockBattery.onBatteryStateChanged)
        .thenAnswer((_) => batteryStateController.stream);
    when(() => mockBattery.getBatteryLevel()).thenAnswer((_) async => 80);
    when(() => mockBattery.getBatteryState())
        .thenAnswer((_) async => BatteryState.discharging);

    when(() => mockNotificationService.sendLocalNotification(
          title: any(named: 'title'),
          body: any(named: 'body'),
        )).thenAnswer((_) async => const Right(null));

    when(() => mockLocationService.getLocation()).thenAnswer((_) async => const Right({
          'latitude': -6.200050,
          'longitude': 106.816670,
        }));

    when(() => mockWorkmanager.initialize(any()))
        .thenAnswer((_) async {});
    when(() => mockWorkmanager.registerPeriodicTask(
          any(),
          any(),
          frequency: any(named: 'frequency'),
          initialDelay: any(named: 'initialDelay'),
          inputData: any(named: 'inputData'),
        )).thenAnswer((_) async {});
    when(() => mockWorkmanager.cancelByUniqueName(any()))
        .thenAnswer((_) async {});
    when(() => mockWorkmanager.cancelAll()).thenAnswer((_) async {});

    service = AmbientTriggerService(
      battery: mockBattery,
      locationService: mockLocationService,
      notificationService: mockNotificationService,
      workmanager: mockWorkmanager,
      batteryCooldownDuration: const Duration(minutes: 30),
      geofenceCooldownDuration: const Duration(minutes: 15),
    );
  });

  tearDown(() {
    batteryStateController.close();
    service.dispose();
  });

  group('Geofence Management', () {
    test('registerGeofence adds region and listGeofences returns it', () async {
      final res = await service.registerGeofence(sampleRegionOffice);
      expect(res.isRight(), isTrue);

      final listRes = await service.listGeofences();
      expect(listRes.isRight(), isTrue);
      final list = listRes.getOrElse(() => []);
      expect(list.length, 1);
      expect(list.first.id, 'office_1');
      expect(service.registeredGeofences.length, 1);
    });

    test('registerGeofence validates latitude and longitude bounds', () async {
      const invalidLat = GeofenceRegion(
        id: 'bad_lat',
        name: 'Bad',
        latitude: 95.0,
        longitude: 10.0,
      );
      final res1 = await service.registerGeofence(invalidLat);
      expect(res1.isLeft(), isTrue);

      const invalidLon = GeofenceRegion(
        id: 'bad_lon',
        name: 'Bad',
        latitude: 0.0,
        longitude: 190.0,
      );
      final res2 = await service.registerGeofence(invalidLon);
      expect(res2.isLeft(), isTrue);

      const invalidRadius = GeofenceRegion(
        id: 'bad_rad',
        name: 'Bad',
        latitude: 0.0,
        longitude: 0.0,
        radiusMeters: -5.0,
      );
      final res3 = await service.registerGeofence(invalidRadius);
      expect(res3.isLeft(), isTrue);
    });

    test('removeGeofence deletes geofence by id', () async {
      await service.registerGeofence(sampleRegionOffice);
      await service.registerGeofence(sampleRegionHome);
      expect(service.registeredGeofences.length, 2);

      final removeRes = await service.removeGeofence('office_1');
      expect(removeRes.isRight(), isTrue);
      expect(service.registeredGeofences.length, 1);
      expect(service.registeredGeofences.first.id, 'home_1');
    });

    test('clearGeofences removes all registered regions', () async {
      await service.registerGeofence(sampleRegionOffice);
      await service.registerGeofence(sampleRegionHome);
      expect(service.registeredGeofences.length, 2);

      final clearRes = await service.clearGeofences();
      expect(clearRes.isRight(), isTrue);
      expect(service.registeredGeofences, isEmpty);
    });
  });

  group('Geofence Transition Triggers & Notifications', () {
    test('outside to inside triggers geofenceEnter event and notification', () async {
      await service.registerGeofence(sampleRegionOffice);

      final eventsReceived = <AmbientEvent>[];
      final sub = service.eventStream.listen(eventsReceived.add);

      // Check 1: User is far away (-6.5, 107.0) -> outside (state: outside)
      final check1 = await service.checkTriggers(
        currentLat: -6.500000,
        currentLon: 107.000000,
        currentBattery: 80,
        isCharging: false,
      );
      expect(check1.isRight(), isTrue);
      expect(eventsReceived, isEmpty);
      verifyNever(() => mockNotificationService.sendLocalNotification(
            title: any(named: 'title'),
            body: any(named: 'body'),
          ));

      // Check 2: User arrives at Office (-6.200050, 106.816670 is ~7 meters away) -> inside
      final check2 = await service.checkTriggers(
        currentLat: -6.200050,
        currentLon: 106.816670,
        currentBattery: 80,
        isCharging: false,
      );
      await pumpEventQueue();
      expect(check2.isRight(), isTrue);
      expect(eventsReceived.length, 1);
      final event = eventsReceived.first;
      expect(event.type, AmbientEventType.geofenceEnter);
      expect(event.title, contains('HQ Office'));
      expect(event.payload['geofence_id'], 'office_1');
      expect(event.recommendedAction, contains('Daily Briefing'));

      verify(() => mockNotificationService.sendLocalNotification(
            title: any(named: 'title', that: contains('HQ Office')),
            body: any(named: 'body', that: contains('briefing')),
          )).called(1);

      // Check 3: User still inside Office on next tick -> NO redundant trigger
      final check3 = await service.checkTriggers(
        currentLat: -6.200055,
        currentLon: 106.816672,
        currentBattery: 80,
        isCharging: false,
      );
      await pumpEventQueue();
      expect(check3.isRight(), isTrue);
      expect(eventsReceived.length, 1);

      await sub.cancel();
    });

    test('inside to outside triggers geofenceExit event if triggerOnExit is true', () async {
      await service.registerGeofence(sampleRegionOffice);

      final eventsReceived = <AmbientEvent>[];
      final sub = service.eventStream.listen(eventsReceived.add);

      // Start inside
      await service.checkTriggers(
        currentLat: -6.200050,
        currentLon: 106.816670,
        currentBattery: 80,
        isCharging: false,
      );
      await pumpEventQueue();
      expect(eventsReceived.length, 1);
      expect(eventsReceived.first.type, AmbientEventType.geofenceEnter);

      // Move outside
      await service.checkTriggers(
        currentLat: -6.500000,
        currentLon: 107.000000,
        currentBattery: 80,
        isCharging: false,
      );
      await pumpEventQueue();
      expect(eventsReceived.length, 2);
      final exitEvent = eventsReceived[1];
      expect(exitEvent.type, AmbientEventType.geofenceExit);
      expect(exitEvent.title, contains('HQ Office'));

      verify(() => mockNotificationService.sendLocalNotification(
            title: any(named: 'title', that: contains('HQ Office')),
            body: any(named: 'body'),
          )).called(2);

      await sub.cancel();
    });

    test('does not trigger geofenceExit if triggerOnExit is false', () async {
      await service.registerGeofence(sampleRegionHome); // triggerOnExit is false

      final eventsReceived = <AmbientEvent>[];
      final sub = service.eventStream.listen(eventsReceived.add);

      // Start inside Home
      await service.checkTriggers(
        currentLat: -6.300050,
        currentLon: 106.900050,
        currentBattery: 80,
        isCharging: false,
      );
      await pumpEventQueue();
      expect(eventsReceived.length, 1);

      // Move outside Home
      await service.checkTriggers(
        currentLat: -6.500000,
        currentLon: 107.000000,
        currentBattery: 80,
        isCharging: false,
      );
      await pumpEventQueue();
      // Still 1 (exit was suppressed)
      expect(eventsReceived.length, 1);

      await sub.cancel();
    });
  });

  group('Battery Watchdog & Threshold Triggers', () {
    test('battery > 15% does not trigger battery warnings', () async {
      final events = <AmbientEvent>[];
      final sub = service.eventStream.listen(events.add);

      final check = await service.checkTriggers(
        currentBattery: 50,
        isCharging: false,
      );
      await pumpEventQueue();
      expect(check.isRight(), isTrue);
      expect(events, isEmpty);
      verifyNever(() => mockNotificationService.sendLocalNotification(
            title: any(named: 'title'),
            body: any(named: 'body'),
          ));

      await sub.cancel();
    });

    test('battery <= 15% and not charging triggers batteryLow event and notification', () async {
      final events = <AmbientEvent>[];
      final sub = service.eventStream.listen(events.add);

      final check = await service.checkTriggers(
        currentBattery: 14,
        isCharging: false,
      );
      await pumpEventQueue();
      expect(check.isRight(), isTrue);
      expect(events.length, 1);
      expect(events.first.type, AmbientEventType.batteryLow);
      expect(events.first.title, contains('14%'));
      expect(events.first.recommendedAction, contains('battery-saving'));

      verify(() => mockNotificationService.sendLocalNotification(
            title: any(named: 'title', that: contains('14%')),
            body: any(named: 'body', that: contains('15%')),
          )).called(1);

      await sub.cancel();
    });

    test('battery <= 5% and not charging triggers batteryCritical event', () async {
      final events = <AmbientEvent>[];
      final sub = service.eventStream.listen(events.add);

      final check = await service.checkTriggers(
        currentBattery: 4,
        isCharging: false,
      );
      await pumpEventQueue();
      expect(check.isRight(), isTrue);
      expect(events.length, 1);
      expect(events.first.type, AmbientEventType.batteryCritical);
      expect(events.first.title, contains('Critical'));
      expect(events.first.title, contains('4%'));

      verify(() => mockNotificationService.sendLocalNotification(
            title: any(named: 'title', that: contains('Critical')),
            body: any(named: 'body'),
          )).called(1);

      await sub.cancel();
    });

    test('charging state suppresses batteryLow and batteryCritical triggers', () async {
      final events = <AmbientEvent>[];
      final sub = service.eventStream.listen(events.add);

      final check = await service.checkTriggers(
        currentBattery: 10,
        isCharging: true, // Charging!
      );
      await pumpEventQueue();
      expect(check.isRight(), isTrue);
      expect(events, isEmpty);
      verifyNever(() => mockNotificationService.sendLocalNotification(
            title: any(named: 'title'),
            body: any(named: 'body'),
          ));

      await sub.cancel();
    });
  });

  group('Cooldown Timers & Deduplication', () {
    test('repeated trigger within cooldown window is suppressed', () async {
      final events = <AmbientEvent>[];
      final sub = service.eventStream.listen(events.add);

      // First trigger: should fire
      await service.checkTriggers(
        currentBattery: 12,
        isCharging: false,
      );
      await pumpEventQueue();
      expect(events.length, 1);
      expect(service.isUnderCooldown('battery_low'), isTrue);

      // Second trigger immediately after: should be suppressed by cooldown
      await service.checkTriggers(
        currentBattery: 11,
        isCharging: false,
      );
      await pumpEventQueue();
      expect(events.length, 1); // No new event added

      verify(() => mockNotificationService.sendLocalNotification(
            title: any(named: 'title'),
            body: any(named: 'body'),
          )).called(1);

      await sub.cancel();
    });

    test('trigger fires again after cooldown duration passes', () async {
      // Create service with very short cooldown for testing
      final shortCooldownService = AmbientTriggerService(
        battery: mockBattery,
        locationService: mockLocationService,
        notificationService: mockNotificationService,
        workmanager: mockWorkmanager,
        batteryCooldownDuration: const Duration(milliseconds: 50),
      );

      final events = <AmbientEvent>[];
      final sub = shortCooldownService.eventStream.listen(events.add);

      // First trigger
      await shortCooldownService.checkTriggers(
        currentBattery: 12,
        isCharging: false,
      );
      await pumpEventQueue();
      expect(events.length, 1);

      // Wait for cooldown to expire
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(shortCooldownService.isUnderCooldown('battery_low'), isFalse);

      // Second trigger after cooldown expires: should fire again
      await shortCooldownService.checkTriggers(
        currentBattery: 10,
        isCharging: false,
      );
      await pumpEventQueue();
      expect(events.length, 2);

      await sub.cancel();
      shortCooldownService.dispose();
    });

    test('resetCooldowns clears all active cooldown timers', () async {
      await service.checkTriggers(
        currentBattery: 12,
        isCharging: false,
      );
      expect(service.isUnderCooldown('battery_low'), isTrue);

      service.resetCooldowns();
      expect(service.isUnderCooldown('battery_low'), isFalse);
    });
  });

  group('Background Periodic Checker & Workmanager', () {
    test('initializeBackgroundChecker initializes workmanager and registers periodic task', () async {
      final res = await service.initializeBackgroundChecker(
        frequency: const Duration(minutes: 15),
      );
      expect(res.isRight(), isTrue);

      verify(() => mockWorkmanager.initialize(
            any(),
          )).called(1);
      verify(() => mockWorkmanager.registerPeriodicTask(
            'ambient_trigger_periodic_checker',
            'ambient_trigger_periodic_task',
            frequency: const Duration(minutes: 15),
            inputData: any(named: 'inputData'),
          )).called(1);
    });

    test('cancelBackgroundChecker cancels periodic task in workmanager', () async {
      final res = await service.cancelBackgroundChecker();
      expect(res.isRight(), isTrue);
      verify(() => mockWorkmanager.cancelByUniqueName('ambient_trigger_periodic_checker'))
          .called(1);
    });

    test('performPeriodicCheck queries battery and location when not provided', () async {
      await service.registerGeofence(sampleRegionOffice);
      when(() => mockBattery.getBatteryLevel()).thenAnswer((_) async => 14);
      when(() => mockBattery.getBatteryState())
          .thenAnswer((_) async => BatteryState.discharging);

      final res = await service.performPeriodicCheck();
      expect(res.isRight(), isTrue);

      final checkResult = res.getOrElse(() => throw Exception());
      expect(checkResult.batteryLevel, 14);
      expect(checkResult.isCharging, false);
      expect(checkResult.currentPosition?['latitude'], -6.200050);
      expect(checkResult.triggeredEvents.length, greaterThanOrEqualTo(1));
    });
  });

  group('Live Stream Monitoring', () {
    test('startMonitoring subscribes to battery stream and dispatches on low battery transition', () async {
      when(() => mockBattery.getBatteryLevel()).thenAnswer((_) async => 12);
      await service.startMonitoring();

      final events = <AmbientEvent>[];
      final sub = service.eventStream.listen(events.add);

      // Emit battery state change
      batteryStateController.add(BatteryState.discharging);

      // Allow microtasks to settle
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events.length, 1);
      expect(events.first.type, AmbientEventType.batteryLow);

      await sub.cancel();
      await service.stopMonitoring();
    });

    test('stopMonitoring stops listening to battery stream', () async {
      await service.startMonitoring();
      await service.stopMonitoring();

      final events = <AmbientEvent>[];
      final sub = service.eventStream.listen(events.add);

      batteryStateController.add(BatteryState.discharging);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(events, isEmpty);
      await sub.cancel();
    });
  });

  group('ToolRegistry Integration', () {
    late ToolRegistry registry;

    setUp(() {
      registry = ToolRegistry();
      registry.registerAmbientTriggerTools(service);
    });

    test('registers all 5 ambient trigger tools in ToolRegistry', () {
      expect(registry.hasTool('register_geofence'), isTrue);
      expect(registry.hasTool('list_geofences'), isTrue);
      expect(registry.hasTool('remove_geofence'), isTrue);
      expect(registry.hasTool('check_ambient_status'), isTrue);
      expect(registry.hasTool('trigger_ambient_check'), isTrue);
    });

    test('executes register_geofence, list_geofences, and remove_geofence tools', () async {
      // 1. register_geofence
      final regRes = await registry.executeTool('register_geofence', {
        'id': 'office_tool',
        'name': 'Office HQ',
        'latitude': -6.2,
        'longitude': 106.8,
        'radius_meters': 250.0,
      });
      expect(regRes.isRight(), isTrue);

      // 2. list_geofences
      final listRes = await registry.executeTool('list_geofences');
      expect(listRes.isRight(), isTrue);
      expect(listRes.getOrElse(() => ''), contains('office_tool'));

      // 3. remove_geofence
      final remRes = await registry.executeTool('remove_geofence', {
        'id': 'office_tool',
      });
      expect(remRes.isRight(), isTrue);

      // verify removed
      final listRes2 = await registry.executeTool('list_geofences');
      expect(listRes2.getOrElse(() => ''), isNot(contains('office_tool')));
    });

    test('executes check_ambient_status and trigger_ambient_check tools', () async {
      final statusRes = await registry.executeTool('check_ambient_status');
      expect(statusRes.isRight(), isTrue);
      expect(statusRes.getOrElse(() => ''), contains('low_battery_threshold'));

      final checkRes = await registry.executeTool('trigger_ambient_check');
      expect(checkRes.isRight(), isTrue);
      expect(checkRes.getOrElse(() => ''), contains('battery_level'));
    });
  });
}
