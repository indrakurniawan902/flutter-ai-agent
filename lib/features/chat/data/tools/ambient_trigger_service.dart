import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:workmanager/workmanager.dart';

import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/models/ambient_event.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/location_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/notification_service.dart';

/// Top-level callback dispatcher required by Workmanager.
@pragma('vm:entry-point')
void ambientWorkmanagerCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    return Future.value(true);
  });
}

/// Abstraction for Battery operations to enable testability.
abstract class BatteryPlatformWrapper {
  Future<int> getBatteryLevel();
  Future<BatteryState> getBatteryState();
  Stream<BatteryState> get onBatteryStateChanged;
}

class DefaultBatteryPlatformWrapper implements BatteryPlatformWrapper {
  final Battery _battery;

  DefaultBatteryPlatformWrapper({Battery? battery})
      : _battery = battery ?? Battery();

  @override
  Future<int> getBatteryLevel() => _battery.batteryLevel;

  @override
  Future<BatteryState> getBatteryState() => _battery.batteryState;

  @override
  Stream<BatteryState> get onBatteryStateChanged =>
      _battery.onBatteryStateChanged;
}

/// Abstraction for Workmanager background operations.
abstract class WorkmanagerPlatformWrapper {
  Future<void> initialize(
    Function callbackDispatcher,
  );

  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? initialDelay,
    Map<String, dynamic>? inputData,
  });

  Future<void> cancelByUniqueName(String uniqueName);

  Future<void> cancelAll();
}

class DefaultWorkmanagerPlatformWrapper implements WorkmanagerPlatformWrapper {
  final Workmanager _workmanager;

  DefaultWorkmanagerPlatformWrapper({Workmanager? workmanager})
      : _workmanager = workmanager ?? Workmanager();

  @override
  Future<void> initialize(
    Function callbackDispatcher,
  ) {
    return _workmanager.initialize(
      callbackDispatcher,
    );
  }

  @override
  Future<void> registerPeriodicTask(
    String uniqueName,
    String taskName, {
    Duration? frequency,
    Duration? initialDelay,
    Map<String, dynamic>? inputData,
  }) {
    return _workmanager.registerPeriodicTask(
      uniqueName,
      taskName,
      frequency: frequency,
      initialDelay: initialDelay,
      inputData: inputData,
    );
  }

  @override
  Future<void> cancelByUniqueName(String uniqueName) {
    return _workmanager.cancelByUniqueName(uniqueName);
  }

  @override
  Future<void> cancelAll() {
    return _workmanager.cancelAll();
  }
}

/// Contract for Ambient Trigger Service.
abstract class AmbientTriggerServiceBase {
  Stream<AmbientEvent> get eventStream;
  List<GeofenceRegion> get registeredGeofences;
  int get lowBatteryThreshold;
  int get criticalBatteryThreshold;
  Duration get batteryCooldownDuration;
  Duration get geofenceCooldownDuration;

  Future<Either<Failure, void>> registerGeofence(GeofenceRegion region);
  Future<Either<Failure, void>> removeGeofence(String id);
  Future<Either<Failure, List<GeofenceRegion>>> listGeofences();
  Future<Either<Failure, void>> clearGeofences();

  Future<Either<Failure, AmbientCheckResult>> checkTriggers({
    double? currentLat,
    double? currentLon,
    int? currentBattery,
    bool? isCharging,
  });

  Future<Either<Failure, AmbientCheckResult>> performPeriodicCheck();

  Future<Either<Failure, void>> startMonitoring();
  Future<void> stopMonitoring();

  Future<Either<Failure, void>> initializeBackgroundChecker({
    Duration? frequency,
  });
  Future<Either<Failure, void>> cancelBackgroundChecker();

  bool isUnderCooldown(String key, {Duration? customCooldown});
  void resetCooldowns();
  void dispose();
}

/// Implementation of [AmbientTriggerServiceBase] providing:
/// - Geofence transition detection (enter/exit)
/// - Battery watchdog (low & critical alerts with charging suppression)
/// - Cooldown timers to prevent trigger flood
/// - Local notifications with daily brief or power saving advice
/// - Periodic background checker integration via Workmanager
class AmbientTriggerService implements AmbientTriggerServiceBase {
  static const String periodicTaskUniqueName =
      'ambient_trigger_periodic_checker';
  static const String periodicTaskName = 'ambient_trigger_periodic_task';

  final BatteryPlatformWrapper _battery;
  final LocationServiceBase _locationService;
  final NotificationServiceBase _notificationService;
  final WorkmanagerPlatformWrapper _workmanager;

  @override
  final int lowBatteryThreshold;
  @override
  final int criticalBatteryThreshold;
  @override
  final Duration batteryCooldownDuration;
  @override
  final Duration geofenceCooldownDuration;

  final Map<String, GeofenceRegion> _geofences = {};
  final Map<String, bool> _regionInsideState = {};
  final Map<String, DateTime> _cooldownTimestamps = {};
  final StreamController<AmbientEvent> _eventStreamController =
      StreamController<AmbientEvent>.broadcast();

  StreamSubscription<BatteryState>? _batterySubscription;
  bool _isMonitoring = false;

  AmbientTriggerService({
    BatteryPlatformWrapper? battery,
    LocationServiceBase? locationService,
    NotificationServiceBase? notificationService,
    WorkmanagerPlatformWrapper? workmanager,
    this.lowBatteryThreshold = 15,
    this.criticalBatteryThreshold = 5,
    this.batteryCooldownDuration = const Duration(minutes: 30),
    this.geofenceCooldownDuration = const Duration(minutes: 15),
  })  : _battery = battery ?? DefaultBatteryPlatformWrapper(),
        _locationService = locationService ?? LocationService(),
        _notificationService = notificationService ?? NotificationService(),
        _workmanager = workmanager ?? DefaultWorkmanagerPlatformWrapper();

  @override
  Stream<AmbientEvent> get eventStream => _eventStreamController.stream;

  @override
  List<GeofenceRegion> get registeredGeofences => _geofences.values.toList();

  @override
  Future<Either<Failure, void>> registerGeofence(GeofenceRegion region) async {
    try {
      if (region.latitude < -90.0 || region.latitude > 90.0) {
        return const Left(
          ValidationFailure('Latitude must be between -90.0 and 90.0'),
        );
      }
      if (region.longitude < -180.0 || region.longitude > 180.0) {
        return const Left(
          ValidationFailure('Longitude must be between -180.0 and 180.0'),
        );
      }
      if (region.radiusMeters <= 0) {
        return const Left(
          ValidationFailure('radiusMeters must be greater than 0'),
        );
      }

      _geofences[region.id] = region;
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure('Failed to register geofence: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> removeGeofence(String id) async {
    try {
      _geofences.remove(id);
      _regionInsideState.remove(id);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure('Failed to remove geofence: $e'));
    }
  }

  @override
  Future<Either<Failure, List<GeofenceRegion>>> listGeofences() async {
    return Right(registeredGeofences);
  }

  @override
  Future<Either<Failure, void>> clearGeofences() async {
    _geofences.clear();
    _regionInsideState.clear();
    return const Right(null);
  }

  @override
  bool isUnderCooldown(String key, {Duration? customCooldown}) {
    final lastTime = _cooldownTimestamps[key];
    if (lastTime == null) return false;

    final cooldown = customCooldown ??
        (key.startsWith('battery_')
            ? batteryCooldownDuration
            : geofenceCooldownDuration);

    final elapsed = DateTime.now().difference(lastTime);
    return elapsed < cooldown;
  }

  void _recordCooldown(String key) {
    _cooldownTimestamps[key] = DateTime.now();
  }

  @override
  void resetCooldowns() {
    _cooldownTimestamps.clear();
  }

  /// Calculates geodesic distance between two points in meters using Haversine formula.
  double _calculateDistanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusMeters = 6371000.0;
    final dLat = (lat2 - lat1) * (math.pi / 180.0);
    final dLon = (lon2 - lon1) * (math.pi / 180.0);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * (math.pi / 180.0)) *
            math.cos(lat2 * (math.pi / 180.0)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMeters * c;
  }

  @override
  Future<Either<Failure, AmbientCheckResult>> checkTriggers({
    double? currentLat,
    double? currentLon,
    int? currentBattery,
    bool? isCharging,
  }) async {
    try {
      final now = DateTime.now();
      final triggeredEvents = <AmbientEvent>[];

      // 1. Evaluate Battery Watchdog
      if (currentBattery != null) {
        final charging = isCharging ?? false;
        if (!charging) {
          if (currentBattery <= criticalBatteryThreshold) {
            const cooldownKey = 'battery_critical';
            if (!isUnderCooldown(cooldownKey)) {
              final event = AmbientEvent(
                id: 'battery_crit_${now.millisecondsSinceEpoch}',
                type: AmbientEventType.batteryCritical,
                timestamp: now,
                title: 'Battery Critical ($currentBattery%)',
                body:
                    'Battery is critically low (< $criticalBatteryThreshold%). Connect charger immediately.',
                payload: {
                  'battery_level': currentBattery,
                  'is_charging': false,
                  'threshold': criticalBatteryThreshold,
                },
                recommendedAction:
                    'Urgent: Connect charger immediately to avoid device shutdown.',
              );
              triggeredEvents.add(event);
              _recordCooldown(cooldownKey);
              await _dispatchNotification(event);
            }
          } else if (currentBattery <= lowBatteryThreshold) {
            const cooldownKey = 'battery_low';
            if (!isUnderCooldown(cooldownKey)) {
              final event = AmbientEvent(
                id: 'battery_low_${now.millisecondsSinceEpoch}',
                type: AmbientEventType.batteryLow,
                timestamp: now,
                title: 'Battery Low ($currentBattery%)',
                body:
                    'Battery is below $lowBatteryThreshold%. Consider enabling battery saver mode.',
                payload: {
                  'battery_level': currentBattery,
                  'is_charging': false,
                  'threshold': lowBatteryThreshold,
                },
                recommendedAction:
                    'Switch to battery-saving mode: reduce background sync and dim screen.',
              );
              triggeredEvents.add(event);
              _recordCooldown(cooldownKey);
              await _dispatchNotification(event);
            }
          }
        }
      }

      // 2. Evaluate Geofence Transitions
      if (currentLat != null && currentLon != null) {
        for (final region in _geofences.values) {
          final distance = _calculateDistanceMeters(
            currentLat,
            currentLon,
            region.latitude,
            region.longitude,
          );

          final isInside = distance <= region.radiusMeters;
          final wasInside = _regionInsideState[region.id];
          _regionInsideState[region.id] = isInside;

          final bool shouldTriggerEnter =
              (!(wasInside ?? false) && isInside && region.triggerOnEnter);
          final bool shouldTriggerExit =
              ((wasInside ?? false) && !isInside && region.triggerOnExit);

          // Outside -> Inside Transition (Enter)
          if (shouldTriggerEnter) {
            final cooldownKey = 'geofence_${region.id}_enter';
            if (!isUnderCooldown(cooldownKey)) {
              final event = AmbientEvent(
                id: 'geofence_enter_${region.id}_${now.millisecondsSinceEpoch}',
                type: AmbientEventType.geofenceEnter,
                timestamp: now,
                title: 'Arrived at ${region.name}',
                body:
                    'Welcome to ${region.name}! Tap for your daily briefing and scheduled tasks.',
                payload: {
                  'geofence_id': region.id,
                  'region_name': region.name,
                  'latitude': currentLat,
                  'longitude': currentLon,
                  'distance_meters': distance,
                  'radius_meters': region.radiusMeters,
                },
                recommendedAction:
                    'Daily Briefing: Checking upcoming calendar events and pending triage items.',
              );
              triggeredEvents.add(event);
              _recordCooldown(cooldownKey);
              await _dispatchNotification(event);
            }
          }

          // Inside -> Outside Transition (Exit)
          if (shouldTriggerExit) {
            final cooldownKey = 'geofence_${region.id}_exit';
            if (!isUnderCooldown(cooldownKey)) {
              final event = AmbientEvent(
                id: 'geofence_exit_${region.id}_${now.millisecondsSinceEpoch}',
                type: AmbientEventType.geofenceExit,
                timestamp: now,
                title: 'Left ${region.name}',
                body: 'You have departed from ${region.name}. Safe travels!',
                payload: {
                  'geofence_id': region.id,
                  'region_name': region.name,
                  'latitude': currentLat,
                  'longitude': currentLon,
                  'distance_meters': distance,
                },
                recommendedAction:
                    'Safe travels: review pending tasks for your trip.',
              );
              triggeredEvents.add(event);
              _recordCooldown(cooldownKey);
              await _dispatchNotification(event);
            }
          }
        }
      }

      // Emit all triggered events to stream
      for (final event in triggeredEvents) {
        if (!_eventStreamController.isClosed) {
          _eventStreamController.add(event);
        }
      }

      final result = AmbientCheckResult(
        batteryLevel: currentBattery,
        isCharging: isCharging,
        currentPosition: (currentLat != null && currentLon != null)
            ? {'latitude': currentLat, 'longitude': currentLon}
            : null,
        triggeredEvents: triggeredEvents,
        timestamp: now,
      );

      return Right(result);
    } catch (e) {
      return Left(ServerFailure('Failed to check ambient triggers: $e'));
    }
  }

  Future<void> _dispatchNotification(AmbientEvent event) async {
    try {
      await _notificationService.sendLocalNotification(
        title: event.title,
        body: event.body,
      );
    } catch (_) {
      // Notification errors do not crash ambient loop
    }
  }

  @override
  Future<Either<Failure, AmbientCheckResult>> performPeriodicCheck() async {
    try {
      int? batteryLevel;
      bool? isCharging;
      double? lat;
      double? lon;

      // Query Battery
      try {
        batteryLevel = await _battery.getBatteryLevel();
        final state = await _battery.getBatteryState();
        isCharging = state == BatteryState.charging;
      } catch (_) {}

      // Query Location
      try {
        final locRes = await _locationService.getLocation();
        locRes.fold(
          (_) {},
          (data) {
            lat = (data['latitude'] as num?)?.toDouble();
            lon = (data['longitude'] as num?)?.toDouble();
          },
        );
      } catch (_) {}

      return await checkTriggers(
        currentLat: lat,
        currentLon: lon,
        currentBattery: batteryLevel,
        isCharging: isCharging,
      );
    } catch (e) {
      return Left(ServerFailure('Periodic ambient check failed: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> startMonitoring() async {
    if (_isMonitoring) return const Right(null);

    try {
      _batterySubscription = _battery.onBatteryStateChanged.listen(
        (state) async {
          if (state == BatteryState.discharging) {
            try {
              final level = await _battery.getBatteryLevel();
              await checkTriggers(
                currentBattery: level,
                isCharging: false,
              );
            } catch (_) {}
          }
        },
      );

      _isMonitoring = true;
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure('Failed to start ambient monitoring: $e'));
    }
  }

  @override
  Future<void> stopMonitoring() async {
    await _batterySubscription?.cancel();
    _batterySubscription = null;
    _isMonitoring = false;
  }

  @override
  Future<Either<Failure, void>> initializeBackgroundChecker({
    Duration? frequency,
  }) async {
    try {
      await _workmanager.initialize(
        ambientWorkmanagerCallbackDispatcher,
      );

      await _workmanager.registerPeriodicTask(
        periodicTaskUniqueName,
        periodicTaskName,
        frequency: frequency ?? const Duration(minutes: 15),
        inputData: const {'task': 'ambient_check'},
      );

      return const Right(null);
    } catch (e) {
      return Left(
        ServerFailure('Failed to initialize background checker: $e'),
      );
    }
  }

  @override
  Future<Either<Failure, void>> cancelBackgroundChecker() async {
    try {
      await _workmanager.cancelByUniqueName(periodicTaskUniqueName);
      return const Right(null);
    } catch (e) {
      return Left(
        ServerFailure('Failed to cancel background checker: $e'),
      );
    }
  }

  @override
  void dispose() {
    stopMonitoring();
    if (!_eventStreamController.isClosed) {
      _eventStreamController.close();
    }
  }
}
