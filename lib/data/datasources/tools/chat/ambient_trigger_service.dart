import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:injectable/injectable.dart';
import 'package:workmanager/workmanager.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/data/datasources/local/action_center/action_center_datasource.dart';
import 'package:flutter_ai_agent/data/models/action_center/action_item_model.dart';
import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/services/geofence/geofence_action_dispatcher.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';

@pragma('vm:entry-point')
void ambientWorkmanagerCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async => true);
}

class DefaultBatteryPlatformWrapper implements BatteryPlatformWrapper {
  DefaultBatteryPlatformWrapper({Battery? battery})
      : _battery = battery ?? Battery();

  final Battery _battery;

  @override
  Future<int> getBatteryLevel() => _battery.batteryLevel;

  @override
  Future<bool> isCharging() async {
    final state = await _battery.batteryState;
    return state == BatteryState.charging;
  }
}

class DefaultWorkmanagerPlatformWrapper
    implements WorkmanagerPlatformWrapper {
  DefaultWorkmanagerPlatformWrapper({Workmanager? workmanager})
      : _workmanager = workmanager ?? Workmanager();

  final Workmanager _workmanager;

  @override
  Future<void> ensureInitialized() {
    return _workmanager.initialize(ambientWorkmanagerCallbackDispatcher);
  }

  @override
  Future<void> registerPeriodicTask({Duration? frequency}) {
    return _workmanager.registerPeriodicTask(
      AmbientTriggerService.ambientPeriodicUniqueName,
      AmbientTriggerService.ambientTaskName,
      frequency: frequency ?? AmbientTriggerService.defaultFrequency,
    );
  }

  @override
  Future<void> cancelAmbientTasks() {
    return _workmanager
        .cancelByUniqueName(AmbientTriggerService.ambientPeriodicUniqueName);
  }
}

@LazySingleton(as: AmbientTriggerServiceBase)
class AmbientTriggerService implements AmbientTriggerServiceBase {
  AmbientTriggerService({
    BatteryPlatformWrapper? battery,
    WorkmanagerPlatformWrapper? workmanager,
    List<GeofenceRegion>? initialRegions,
    ActionCenterDatasource? actionCenterDatasource,
    GeofenceActionDispatcherBase? actionDispatcher,
    this.lowThreshold = defaultLowThreshold,
    this.criticalThreshold = defaultCriticalThreshold,
    this.cooldown = defaultCooldown,
  })  : _battery = battery ?? DefaultBatteryPlatformWrapper(),
        _workmanager = workmanager ?? DefaultWorkmanagerPlatformWrapper(),
        _actionCenterDatasource = actionCenterDatasource,
        _actionDispatcher = actionDispatcher,
        _regions = List<GeofenceRegion>.from(initialRegions ?? const []);

  @factoryMethod
  factory AmbientTriggerService.create([
    GeofenceActionDispatcherBase? actionDispatcher,
  ]) =>
      AmbientTriggerService(actionDispatcher: actionDispatcher);

  static const String ambientPeriodicUniqueName = 'ambient_trigger_periodic';
  static const String ambientTaskName = 'ambientTriggerCheck';
  static const int defaultLowThreshold = 20;
  static const int defaultCriticalThreshold = 10;
  static const Duration defaultCooldown = Duration(hours: 1);
  static const Duration defaultFrequency = Duration(minutes: 15);

  final BatteryPlatformWrapper _battery;
  final WorkmanagerPlatformWrapper _workmanager;

  /// Optional Action Center inbox mirror. When null (the default, and the
  /// only mode used by dependency injection) ambient checks behave exactly
  /// as before and nothing is mirrored.
  final ActionCenterDatasource? _actionCenterDatasource;

  /// Optional executor for the action bound to a crossed region. Null (or a
  /// region bound to [GeofenceAction.none]) keeps the check notification-only.
  final GeofenceActionDispatcherBase? _actionDispatcher;

  final List<GeofenceRegion> _regions;
  final Map<String, bool> _insideState = {};
  final Map<String, DateTime> _lastFired = {};

  @override
  final int lowThreshold;

  @override
  final int criticalThreshold;

  @override
  final Duration cooldown;

  @override
  List<GeofenceRegion> get regions => List<GeofenceRegion>.unmodifiable(_regions);

  @override
  void addGeofence(GeofenceRegion region) {
    _regions.removeWhere((r) => r.id == region.id);
    _regions.add(region);
  }

  @override
  void removeGeofence(String id) {
    _regions.removeWhere((r) => r.id == id);
    _insideState.remove(id);
  }

  @override
  void toggleGeofence(String id, bool isEnabled) {
    final index = _regions.indexWhere((r) => r.id == id);
    if (index != -1) {
      _regions[index] = _regions[index].copyWith(isEnabled: isEnabled);
      if (!isEnabled) {
        _insideState.remove(id);
      }
    }
  }

  @override
  void clearGeofences() {
    _regions.clear();
    _insideState.clear();
  }

  @override
  void clearCooldowns() {
    _lastFired.clear();
  }

  bool _isCoolingDown(String key, DateTime now) {
    final last = _lastFired[key];
    if (last == null) return false;
    return now.difference(last) < cooldown;
  }

  void _markFired(String key, DateTime now) {
    _lastFired[key] = now;
  }

  /// Mirrors every triggered [AmbientEvent] into the Action Center inbox as an
  /// unread [ActionItemModel].
  ///
  /// Never throws: inbox mirroring is best-effort and must not change the
  /// ambient check result returned to the caller.
  Future<void> _mirrorEventsToActionCenter(List<AmbientEvent> events) async {
    final datasource = _actionCenterDatasource;
    if (datasource == null || events.isEmpty) return;
    for (final event in events) {
      try {
        await datasource.addItem(_toActionItem(event));
      } catch (_) {
        // Swallow: a failed mirror must never break the ambient check.
      }
    }
  }

  /// Executes each fired event's bound region action.
  ///
  /// Never throws: the dispatcher is best-effort by contract and a region that
  /// no longer exists is skipped, so the ambient check result is unaffected.
  Future<void> _dispatchBoundActions(List<AmbientEvent> events) async {
    final dispatcher = _actionDispatcher;
    if (dispatcher == null || events.isEmpty) return;
    for (final event in events) {
      final regionId = event.regionId;
      if (regionId == null) continue;
      final index = _regions.indexWhere((r) => r.id == regionId);
      if (index == -1) continue;
      try {
        await dispatcher.dispatch(_regions[index], event);
      } catch (_) {
        // Swallow: a failed action must never break the ambient check.
      }
    }
  }

  ActionItemModel _toActionItem(AmbientEvent event) {
    final typeName = event.type.name;
    final isBattery = typeName.startsWith('battery');
    return ActionItemModel(
      id: event.id,
      title: event.title,
      summary: event.body,
      timestamp: event.timestamp,
      priority: event.type == AmbientEventType.batteryCritical
          ? ActionItemPriority.high
          : ActionItemPriority.normal,
      isRead: false,
      source: isBattery ? 'battery_watchdog' : 'geofence',
      actionPayload: event.batteryLevel != null
          ? <String, dynamic>{'batteryLevel': event.batteryLevel}
          : <String, dynamic>{'type': event.type.name},
    );
  }

  @override
  double distanceMeters(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    const earthRadius = 6371000.0;
    final dLat = _toRadians(endLatitude - startLatitude);
    final dLon = _toRadians(endLongitude - startLongitude);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRadians(startLatitude)) *
            math.cos(_toRadians(endLatitude)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  double _toRadians(double degrees) => degrees * math.pi / 180.0;

  @override
  Future<Either<Failure, AmbientCheckResult>> checkBattery({
    DateTime? now,
  }) async {
    try {
      final current = now ?? DateTime.now();
      final level = await _battery.getBatteryLevel();
      final charging = await _battery.isCharging();
      if (charging) {
        return Right(AmbientCheckResult.empty(checkedAt: current));
      }
      if (level <= criticalThreshold) {
        const key = 'battery_critical';
        if (_isCoolingDown(key, current)) {
          return Right(AmbientCheckResult.empty(checkedAt: current));
        }
        _markFired(key, current);
        final event = AmbientEvent(
          id: '${key}_${current.millisecondsSinceEpoch}',
          type: AmbientEventType.batteryCritical,
          title: 'Battery critical',
          body: 'Battery level is $level%. Connect charger.',
          timestamp: current,
          batteryLevel: level,
        );
        await _mirrorEventsToActionCenter([event]);
        return Right(
          AmbientCheckResult(
            triggered: true,
            events: [event],
            checkedAt: current,
          ),
        );
      }
      if (level <= lowThreshold) {
        const key = 'battery_low';
        if (_isCoolingDown(key, current)) {
          return Right(AmbientCheckResult.empty(checkedAt: current));
        }
        _markFired(key, current);
        final event = AmbientEvent(
          id: '${key}_${current.millisecondsSinceEpoch}',
          type: AmbientEventType.batteryLow,
          title: 'Battery low',
          body: 'Battery level is $level%. Low power mode suggested.',
          timestamp: current,
          batteryLevel: level,
        );
        await _mirrorEventsToActionCenter([event]);
        return Right(
          AmbientCheckResult(
            triggered: true,
            events: [event],
            checkedAt: current,
          ),
        );
      }
      return Right(AmbientCheckResult.empty(checkedAt: current));
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Ambient battery check error'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, AmbientCheckResult>> checkGeofence({
    required double latitude,
    required double longitude,
    DateTime? now,
  }) async {
    try {
      final current = now ?? DateTime.now();
      final fired = <AmbientEvent>[];
      for (final region in _regions) {
        if (!region.isEnabled) continue;
        final distance = distanceMeters(
          latitude,
          longitude,
          region.latitude,
          region.longitude,
        );
        final inside = distance <= region.radiusMeters;
        final wasInside = _insideState[region.id] ?? false;
        if (inside && !wasInside) {
          final key = 'geofence_enter_${region.id}';
          if (!_isCoolingDown(key, current)) {
            fired.add(
              AmbientEvent(
                id: '${key}_${current.millisecondsSinceEpoch}',
                type: AmbientEventType.geofenceEnter,
                title: 'Entered ${region.id}',
                body: 'Entered geofence ${region.id}.',
                timestamp: current,
                regionId: region.id,
              ),
            );
            _markFired(key, current);
          }
        } else if (!inside && wasInside) {
          final key = 'geofence_exit_${region.id}';
          if (!_isCoolingDown(key, current)) {
            fired.add(
              AmbientEvent(
                id: '${key}_${current.millisecondsSinceEpoch}',
                type: AmbientEventType.geofenceExit,
                title: 'Exited ${region.id}',
                body: 'Exited geofence ${region.id}.',
                timestamp: current,
                regionId: region.id,
              ),
            );
            _markFired(key, current);
          }
        }
        _insideState[region.id] = inside;
      }
      await _mirrorEventsToActionCenter(fired);
      await _dispatchBoundActions(fired);
      return Right(
        AmbientCheckResult(
          triggered: fired.isNotEmpty,
          events: fired,
          checkedAt: current,
        ),
      );
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Ambient geofence check error'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, AmbientCheckResult>> checkAll({
    double? latitude,
    double? longitude,
    DateTime? now,
  }) async {
    try {
      final current = now ?? DateTime.now();
      final batteryResult = await checkBattery(now: current);
      if (batteryResult.isLeft()) {
        return batteryResult;
      }
      final combined = <AmbientEvent>[
        ...batteryResult.getOrElse(() => AmbientCheckResult.empty()).events,
      ];
      if (latitude != null && longitude != null) {
        final geoResult = await checkGeofence(
          latitude: latitude,
          longitude: longitude,
          now: current,
        );
        if (geoResult.isLeft()) {
          return geoResult;
        }
        combined.addAll(
          geoResult.getOrElse(() => AmbientCheckResult.empty()).events,
        );
      }
      return Right(
        AmbientCheckResult(
          triggered: combined.isNotEmpty,
          events: combined,
          checkedAt: current,
        ),
      );
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Ambient check error'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, void>> schedulePeriodicCheck({
    Duration? frequency,
  }) async {
    try {
      await _workmanager.ensureInitialized();
      await _workmanager.registerPeriodicTask(
        frequency: frequency ?? defaultFrequency,
      );
      return const Right<Failure, void>(null);
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Ambient schedule error'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, void>> cancelPeriodicCheck() async {
    try {
      await _workmanager.cancelAmbientTasks();
      return const Right<Failure, void>(null);
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Ambient cancel error'),
        ),
      );
    }
  }
}
