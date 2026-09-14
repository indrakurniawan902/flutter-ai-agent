import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';

abstract class BatteryPlatformWrapper {
  Future<int> getBatteryLevel();
  Future<bool> isCharging();
}

abstract class WorkmanagerPlatformWrapper {
  Future<void> ensureInitialized();
  Future<void> registerPeriodicTask({Duration? frequency});
  Future<void> cancelAmbientTasks();
}

abstract class AmbientTriggerServiceBase {
  List<GeofenceRegion> get regions;

  int get lowThreshold;

  int get criticalThreshold;

  Duration get cooldown;

  void addGeofence(GeofenceRegion region);

  void removeGeofence(String id);

  void toggleGeofence(String id, bool isEnabled);

  void clearGeofences();

  void clearCooldowns();

  double distanceMeters(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  );

  Future<Either<Failure, AmbientCheckResult>> checkBattery({DateTime? now});

  Future<Either<Failure, AmbientCheckResult>> checkGeofence({
    required double latitude,
    required double longitude,
    DateTime? now,
  });

  Future<Either<Failure, AmbientCheckResult>> checkAll({
    double? latitude,
    double? longitude,
    DateTime? now,
  });

  Future<Either<Failure, void>> schedulePeriodicCheck({Duration? frequency});

  Future<Either<Failure, void>> cancelPeriodicCheck();
}
