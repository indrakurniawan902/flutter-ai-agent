import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockBatteryPlatformWrapper mockBattery;
  late MockWorkmanagerPlatformWrapper mockWorkmanager;
  late AmbientTriggerService service;

  final fixedTime = DateTime(2026, 9, 12, 10, 0, 0);

  const homeRegion = GeofenceRegion(
    id: 'home',
    latitude: 1.0,
    longitude: 2.0,
    radiusMeters: 200.0,
  );

  setUp(() {
    mockBattery = MockBatteryPlatformWrapper();
    mockWorkmanager = MockWorkmanagerPlatformWrapper();
    service = AmbientTriggerService(
      battery: mockBattery,
      workmanager: mockWorkmanager,
    );
  });

  setUpAll(() {
    registerFallbackValue(const Duration(minutes: 15));
  });

  void stubBattery({required int level, required bool charging}) {
    when(() => mockBattery.getBatteryLevel()).thenAnswer((_) async => level);
    when(() => mockBattery.isCharging()).thenAnswer((_) async => charging);
  }

  group('constructor and regions', () {
    test('create factory returns instance with defaults', () {
      final created = AmbientTriggerService.create();
      expect(created.lowThreshold, AmbientTriggerService.defaultLowThreshold);
      expect(
        created.criticalThreshold,
        AmbientTriggerService.defaultCriticalThreshold,
      );
      expect(created.cooldown, AmbientTriggerService.defaultCooldown);
      expect(created.regions, isEmpty);
    });

    test('exposes default constants', () {
      expect(AmbientTriggerService.defaultLowThreshold, 20);
      expect(AmbientTriggerService.defaultCriticalThreshold, 10);
      expect(
        AmbientTriggerService.ambientPeriodicUniqueName,
        'ambient_trigger_periodic',
      );
      expect(AmbientTriggerService.ambientTaskName, 'ambientTriggerCheck');
    });

    test('addGeofence adds and replaces same id', () {
      service.addGeofence(homeRegion);
      expect(service.regions, [homeRegion]);

      const updated = GeofenceRegion(
        id: 'home',
        latitude: 5.0,
        longitude: 6.0,
        radiusMeters: 500.0,
      );
      service.addGeofence(updated);
      expect(service.regions.length, 1);
      expect(service.regions.first, updated);
    });

    test('removeGeofence removes region', () {
      service.addGeofence(homeRegion);
      service.removeGeofence('home');
      expect(service.regions, isEmpty);
    });

    test('toggleGeofence toggles isEnabled state', () {
      service.addGeofence(homeRegion);
      expect(service.regions.first.isEnabled, isTrue);

      service.toggleGeofence('home', false);
      expect(service.regions.first.isEnabled, isFalse);

      service.toggleGeofence('home', true);
      expect(service.regions.first.isEnabled, isTrue);
    });

    test('toggleGeofence ignores unknown region id', () {
      service.addGeofence(homeRegion);
      service.toggleGeofence('unknown', false);
      expect(service.regions.first.isEnabled, isTrue);
    });

    test('toggleGeofence false clears inside state', () async {
      service.addGeofence(homeRegion);
      await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );

      service.toggleGeofence('home', false);
      service.toggleGeofence('home', true);
      service.clearCooldowns();

      final enterAgain = await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime.add(const Duration(minutes: 5)),
      );
      final data = enterAgain.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isTrue);
      expect(data.events.first.type, AmbientEventType.geofenceEnter);
    });

    test('clearGeofences empties regions', () {
      service.addGeofence(homeRegion);
      service.clearGeofences();
      expect(service.regions, isEmpty);
    });

    test('regions returns unmodifiable list', () {
      service.addGeofence(homeRegion);
      expect(() => service.regions.add(homeRegion), throwsUnsupportedError);
    });

    test('initialRegions are copied', () {
      final withInitial = AmbientTriggerService(
        battery: mockBattery,
        workmanager: mockWorkmanager,
        initialRegions: const [homeRegion],
      );
      expect(withInitial.regions, [homeRegion]);
    });
  });

  group('distanceMeters (haversine)', () {
    test('returns zero for same point', () {
      expect(service.distanceMeters(1.0, 2.0, 1.0, 2.0), 0.0);
    });

    test('computes ~111km per degree latitude', () {
      final distance = service.distanceMeters(0.0, 0.0, 1.0, 0.0);
      expect(distance, greaterThan(110000));
      expect(distance, lessThan(112000));
    });

    test('is symmetric', () {
      final a = service.distanceMeters(1.0, 2.0, 3.0, 4.0);
      final b = service.distanceMeters(3.0, 4.0, 1.0, 2.0);
      expect(a, closeTo(b, 0.001));
    });
  });

  group('checkBattery watchdog', () {
    test('emits critical event at or below critical threshold', () async {
      stubBattery(level: 8, charging: false);

      final result = await service.checkBattery(now: fixedTime);

      expect(result.isRight(), isTrue);
      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isTrue);
      expect(data.events.length, 1);
      expect(data.events.first.type, AmbientEventType.batteryCritical);
      expect(data.events.first.batteryLevel, 8);
      expect(data.checkedAt, fixedTime);
    });

    test('emits critical exactly at threshold boundary', () async {
      stubBattery(level: 10, charging: false);

      final result = await service.checkBattery(now: fixedTime);

      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isTrue);
      expect(data.events.first.type, AmbientEventType.batteryCritical);
    });

    test('emits low event between critical and low thresholds', () async {
      stubBattery(level: 15, charging: false);

      final result = await service.checkBattery(now: fixedTime);

      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isTrue);
      expect(data.events.first.type, AmbientEventType.batteryLow);
      expect(data.events.first.batteryLevel, 15);
    });

    test('emits low exactly at low threshold', () async {
      stubBattery(level: 20, charging: false);

      final result = await service.checkBattery(now: fixedTime);

      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isTrue);
      expect(data.events.first.type, AmbientEventType.batteryLow);
    });

    test('returns empty when battery healthy', () async {
      stubBattery(level: 85, charging: false);

      final result = await service.checkBattery(now: fixedTime);

      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isFalse);
      expect(data.events, isEmpty);
    });

    test('suppresses low alert while charging', () async {
      stubBattery(level: 12, charging: true);

      final result = await service.checkBattery(now: fixedTime);

      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isFalse);
      expect(data.events, isEmpty);
    });

    test('suppresses critical alert while charging', () async {
      stubBattery(level: 5, charging: true);

      final result = await service.checkBattery(now: fixedTime);

      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isFalse);
    });

    test('applies cooldown to repeated low alerts', () async {
      stubBattery(level: 15, charging: false);

      final first = await service.checkBattery(now: fixedTime);
      expect(
        first.getOrElse(() => AmbientCheckResult.empty()).triggered,
        isTrue,
      );

      final second = await service.checkBattery(
        now: fixedTime.add(const Duration(minutes: 10)),
      );
      expect(
        second.getOrElse(() => AmbientCheckResult.empty()).triggered,
        isFalse,
      );
    });

    test('fires again after cooldown expires', () async {
      stubBattery(level: 15, charging: false);

      await service.checkBattery(now: fixedTime);
      final later = await service.checkBattery(
        now: fixedTime.add(const Duration(hours: 2)),
      );
      expect(
        later.getOrElse(() => AmbientCheckResult.empty()).triggered,
        isTrue,
      );
    });

    test('clearCooldowns resets suppression', () async {
      stubBattery(level: 15, charging: false);

      await service.checkBattery(now: fixedTime);
      service.clearCooldowns();
      final result = await service.checkBattery(
        now: fixedTime.add(const Duration(minutes: 5)),
      );
      expect(
        result.getOrElse(() => AmbientCheckResult.empty()).triggered,
        isTrue,
      );
    });

    test('returns ServerFailure when battery throws', () async {
      when(() => mockBattery.getBatteryLevel())
          .thenThrow(Exception('sensor fail'));

      final result = await service.checkBattery(now: fixedTime);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Ambient battery check error'));
        },
        (_) => fail('expected Left'),
      );
    });

    test('returns ServerFailure when isCharging throws', () async {
      when(() => mockBattery.getBatteryLevel()).thenAnswer((_) async => 50);
      when(() => mockBattery.isCharging()).thenThrow(Exception('state fail'));

      final result = await service.checkBattery(now: fixedTime);

      expect(result.isLeft(), isTrue);
    });
  });

  group('checkGeofence enter/exit', () {
    test('returns empty when no regions registered', () async {
      final result = await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );

      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isFalse);
      expect(data.events, isEmpty);
    });

    test('fires enter when moving inside region', () async {
      service.addGeofence(homeRegion);

      final result = await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );

      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isTrue);
      expect(data.events.length, 1);
      expect(data.events.first.type, AmbientEventType.geofenceEnter);
      expect(data.events.first.regionId, 'home');
    });

    test('does not refire enter while staying inside', () async {
      service.addGeofence(homeRegion);

      await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );
      final second = await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime.add(const Duration(minutes: 5)),
      );

      expect(
        second.getOrElse(() => AmbientCheckResult.empty()).triggered,
        isFalse,
      );
    });

    test('fires exit when leaving region', () async {
      service.addGeofence(homeRegion);

      await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );
      final exit = await service.checkGeofence(
        latitude: 50.0,
        longitude: 50.0,
        now: fixedTime.add(const Duration(minutes: 5)),
      );

      final data = exit.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isTrue);
      expect(data.events.first.type, AmbientEventType.geofenceExit);
      expect(data.events.first.regionId, 'home');
    });

    test('stays silent while remaining outside', () async {
      service.addGeofence(homeRegion);

      final first = await service.checkGeofence(
        latitude: 50.0,
        longitude: 50.0,
        now: fixedTime,
      );
      final second = await service.checkGeofence(
        latitude: 51.0,
        longitude: 51.0,
        now: fixedTime.add(const Duration(minutes: 5)),
      );

      expect(
        first.getOrElse(() => AmbientCheckResult.empty()).triggered,
        isFalse,
      );
      expect(
        second.getOrElse(() => AmbientCheckResult.empty()).triggered,
        isFalse,
      );
    });

    test('applies cooldown to re-enter', () async {
      final shortCooldownService = AmbientTriggerService(
        battery: mockBattery,
        workmanager: mockWorkmanager,
        cooldown: const Duration(hours: 1),
      );
      shortCooldownService.addGeofence(homeRegion);

      await shortCooldownService.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );
      await shortCooldownService.checkGeofence(
        latitude: 50.0,
        longitude: 50.0,
        now: fixedTime.add(const Duration(minutes: 5)),
      );
      shortCooldownService.clearCooldowns();
      final reenter = await shortCooldownService.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime.add(const Duration(minutes: 10)),
      );
      expect(
        reenter.getOrElse(() => AmbientCheckResult.empty()).triggered,
        isTrue,
      );
    });

    test('suppresses re-enter within cooldown', () async {
      service.addGeofence(homeRegion);

      await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );
      await service.checkGeofence(
        latitude: 50.0,
        longitude: 50.0,
        now: fixedTime.add(const Duration(minutes: 5)),
      );
      final reenter = await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime.add(const Duration(minutes: 10)),
      );
      expect(
        reenter.getOrElse(() => AmbientCheckResult.empty()).triggered,
        isFalse,
      );
    });

    test('skips disabled geofences and does not emit enter or exit', () async {
      const disabledRegion = GeofenceRegion(
        id: 'office',
        latitude: 10.0,
        longitude: 20.0,
        radiusMeters: 500.0,
        isEnabled: false,
      );
      service.addGeofence(disabledRegion);

      final result = await service.checkGeofence(
        latitude: 10.0,
        longitude: 20.0,
        now: fixedTime,
      );

      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isFalse);
      expect(data.events, isEmpty);
    });
  });

  group('checkAll', () {
    test('combines battery and geofence events', () async {
      stubBattery(level: 8, charging: false);
      service.addGeofence(homeRegion);

      final result = await service.checkAll(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );

      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isTrue);
      expect(data.events.length, 2);
      expect(
        data.events.map((e) => e.type),
        containsAll([
          AmbientEventType.batteryCritical,
          AmbientEventType.geofenceEnter,
        ]),
      );
    });

    test('returns battery only when no coordinates', () async {
      stubBattery(level: 15, charging: false);

      final result = await service.checkAll(now: fixedTime);

      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isTrue);
      expect(data.events.length, 1);
      expect(data.events.first.type, AmbientEventType.batteryLow);
    });

    test('returns empty when nothing triggered', () async {
      stubBattery(level: 90, charging: false);

      final result = await service.checkAll(now: fixedTime);

      final data = result.getOrElse(() => AmbientCheckResult.empty());
      expect(data.triggered, isFalse);
      expect(data.events, isEmpty);
    });

    test('propagates battery failure', () async {
      when(() => mockBattery.getBatteryLevel())
          .thenThrow(Exception('battery down'));

      final result = await service.checkAll(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('workmanager registration', () {
    test('schedulePeriodicCheck registers task and returns Right', () async {
      when(() => mockWorkmanager.ensureInitialized())
          .thenAnswer((_) => Future<void>.value());
      when(
        () => mockWorkmanager.registerPeriodicTask(
          frequency: any(named: 'frequency'),
        ),
      ).thenAnswer((_) => Future<void>.value());

      final result = await service.schedulePeriodicCheck();

      expect(result.isRight(), isTrue);
      verify(() => mockWorkmanager.ensureInitialized()).called(1);
      verify(
        () => mockWorkmanager.registerPeriodicTask(
          frequency: any(named: 'frequency'),
        ),
      ).called(1);
    });

    test('schedulePeriodicCheck passes custom frequency', () async {
      when(() => mockWorkmanager.ensureInitialized())
          .thenAnswer((_) => Future<void>.value());
      when(
        () => mockWorkmanager.registerPeriodicTask(
          frequency: any(named: 'frequency'),
        ),
      ).thenAnswer((_) => Future<void>.value());

      const custom = Duration(minutes: 30);
      final result = await service.schedulePeriodicCheck(frequency: custom);

      expect(result.isRight(), isTrue);
      verify(
        () => mockWorkmanager.registerPeriodicTask(frequency: custom),
      ).called(1);
    });

    test('schedulePeriodicCheck returns failure when wrapper throws', () async {
      when(() => mockWorkmanager.ensureInitialized())
          .thenThrow(Exception('wm fail'));

      final result = await service.schedulePeriodicCheck();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Ambient schedule error'));
        },
        (_) => fail('expected Left'),
      );
    });

    test('cancelPeriodicCheck returns Right on success', () async {
      when(() => mockWorkmanager.cancelAmbientTasks())
          .thenAnswer((_) => Future<void>.value());

      final result = await service.cancelPeriodicCheck();

      expect(result.isRight(), isTrue);
      verify(() => mockWorkmanager.cancelAmbientTasks()).called(1);
    });

    test('cancelPeriodicCheck returns failure when wrapper throws', () async {
      when(() => mockWorkmanager.cancelAmbientTasks())
          .thenThrow(Exception('cancel fail'));

      final result = await service.cancelPeriodicCheck();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Ambient cancel error'));
        },
        (_) => fail('expected Left'),
      );
    });
  });

  group('platform wrappers and dispatcher', () {
    test('DefaultBatteryPlatformWrapper can be constructed', () {
      expect(DefaultBatteryPlatformWrapper(), isA<BatteryPlatformWrapper>());
    });

    test('DefaultWorkmanagerPlatformWrapper can be constructed', () {
      expect(
        DefaultWorkmanagerPlatformWrapper(),
        isA<WorkmanagerPlatformWrapper>(),
      );
    });

    test('ambientWorkmanagerCallbackDispatcher is a top-level function', () {
      expect(ambientWorkmanagerCallbackDispatcher, isA<Function>());
    });
  });
}
