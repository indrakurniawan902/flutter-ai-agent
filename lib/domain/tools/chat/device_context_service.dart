import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/core/errors/failures.dart';

/// Abstraction for device context operations.
///
/// Tools:
///  - device_status: Tier 1 (auto-approved)
///  - system_info: Tier 1 (auto-approved)
abstract class DeviceContextServiceBase {
  /// Returns device status including battery %, charging state, and connectivity.
  Future<Either<Failure, Map<String, dynamic>>> deviceStatus();

  /// Returns system info including model, OS version, app version, screen specs.
  Future<Either<Failure, Map<String, dynamic>>> systemInfo();

  /// Formatted JSON string of device status matching OpenAI tool response format.
  Future<Either<Failure, String>> deviceStatusFormattedJson();

  /// Formatted JSON string of system info matching OpenAI tool response format.
  Future<Either<Failure, String>> systemInfoFormattedJson();
}
