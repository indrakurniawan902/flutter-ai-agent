import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

abstract class BatteryOptimizationPlatformWrapper {
  Future<bool> isIgnoringBatteryOptimizations();
  Future<bool> requestIgnoreBatteryOptimizations();
}

abstract class BatteryOptimizationServiceBase {
  Future<Either<Failure, bool>> isBatteryOptimizationDisabled();
  Future<Either<Failure, bool>> requestDisableBatteryOptimization();
}
