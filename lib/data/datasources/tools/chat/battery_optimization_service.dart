import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/battery_optimization_service.dart';

class DefaultBatteryOptimizationPlatformWrapper
    implements BatteryOptimizationPlatformWrapper {
  static const MethodChannel _channel =
      MethodChannel('ai.hermes.flames/battery_optimization');

  @override
  Future<bool> isIgnoringBatteryOptimizations() async {
    try {
      return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> requestIgnoreBatteryOptimizations() async {
    try {
      return await _channel
              .invokeMethod<bool>('requestIgnoreBatteryOptimizations') ??
          false;
    } catch (_) {
      return false;
    }
  }
}

@LazySingleton(as: BatteryOptimizationServiceBase)
class BatteryOptimizationService implements BatteryOptimizationServiceBase {
  final BatteryOptimizationPlatformWrapper _platform;

  BatteryOptimizationService({
    BatteryOptimizationPlatformWrapper? platformWrapper,
  }) : _platform =
            platformWrapper ?? DefaultBatteryOptimizationPlatformWrapper();

  @factoryMethod
  factory BatteryOptimizationService.create() => BatteryOptimizationService();

  @override
  Future<Either<Failure, bool>> isBatteryOptimizationDisabled() async {
    try {
      final isIgnoring = await _platform.isIgnoringBatteryOptimizations();
      return Right(isIgnoring);
    } catch (e) {
      return Left(ServerFailure('Failed to check battery optimization: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> requestDisableBatteryOptimization() async {
    try {
      final requested = await _platform.requestIgnoreBatteryOptimizations();
      return Right(requested);
    } catch (e) {
      return Left(ServerFailure('Failed to request battery optimization disable: $e'));
    }
  }
}
