import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/health_metrics.dart';
import 'package:flutter_ai_agent/domain/tools/chat/health_service.dart';

abstract class HealthPlatformWrapper {
  Future<Map<String, dynamic>?> availability();
  Future<List<String>> grantedPermissions();
  Future<bool> requestPermission();
  Future<Map<String, dynamic>?> readMetric({
    required String metric,
    required int startTimeMs,
    required int endTimeMs,
  });
}

class DefaultHealthPlatformWrapper implements HealthPlatformWrapper {
  static const MethodChannel _channel = MethodChannel(
    'ai.hermes.flames/health',
  );

  /// A silent platform call (Health Connect readRecords that never replies)
  /// must not suspend the caller forever; the timeout throws into the existing
  /// catch, which maps it to null / empty / false.
  static const Duration _platformCallTimeout = Duration(seconds: 8);

  @override
  Future<Map<String, dynamic>?> availability() async {
    try {
      final raw = await _channel
          .invokeMethod<Map>('availability')
          .timeout(_platformCallTimeout);
      return raw?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> grantedPermissions() async {
    try {
      final result = await _channel
          .invokeMethod<List>('grantedPermissions')
          .timeout(_platformCallTimeout);
      return result?.cast<String>() ?? <String>[];
    } catch (_) {
      return <String>[];
    }
  }

  @override
  Future<bool> requestPermission() async {
    try {
      return await _channel
              .invokeMethod<bool>('requestPermission')
              .timeout(_platformCallTimeout) ??
          false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Map<String, dynamic>?> readMetric({
    required String metric,
    required int startTimeMs,
    required int endTimeMs,
  }) async {
    try {
      final raw = await _channel
          .invokeMethod<Map>(
            'readMetric',
            <String, dynamic>{
              'metric': metric,
              'startTimeMs': startTimeMs,
              'endTimeMs': endTimeMs,
            },
          )
          .timeout(_platformCallTimeout);
      return raw?.cast<String, dynamic>();
    } catch (_) {
      return null;
    }
  }
}

@LazySingleton(as: HealthServiceBase)
class HealthService implements HealthServiceBase {
  /// Upper bound for every platform call this service makes. Any
  /// [HealthPlatformWrapper] implementation can silently never complete, so the
  /// bound lives here where every call routes through - not inside one concrete
  /// wrapper. Deliberately below `ToolRegistry.toolExecutionTimeout` (10s) and
  /// the bridge's 30s budget so callers see a structured failure, not a hang.
  static const Duration platformCallTimeout = Duration(seconds: 8);

  final HealthPlatformWrapper _platform;

  HealthService({HealthPlatformWrapper? platform})
    : _platform = platform ?? DefaultHealthPlatformWrapper();

  @factoryMethod
  factory HealthService.create() => HealthService();

  /// Returns `null` when [future] did not answer inside [platformCallTimeout]
  /// ("silent"), which is NOT the same as an empty answer. Errors the platform
  /// itself raises still propagate to the caller's existing catch so the
  /// failure mapping stays unchanged.
  Future<T?> _bounded<T>(Future<T> future) async {
    try {
      return await future.timeout(platformCallTimeout);
    } on TimeoutException {
      return null;
    }
  }

  @override
  Future<Either<Failure, String>> healthStatusFormattedJson() async {
    try {
      final availability = await _bounded(_platform.availability());
      if (availability == null) {
        return const Left(
          ServerFailure(
            'health_unavailable: Health Connect bridge is not reachable on this device',
          ),
        );
      }
      final status = availability['status'] as String? ?? 'unavailable';
      final sdkInt = (availability['sdk_int'] as num?)?.toInt() ?? 0;
      final grantedPermissions = await _bounded(
        _platform.grantedPermissions(),
      );
      if (grantedPermissions == null) {
        return const Left(
          ServerFailure(
            'health_status_failed: no response from Health Connect for granted permissions',
          ),
        );
      }

      final grantedMetrics = <String>[];
      final missingMetrics = <String>[];
      for (final metric in HealthMetrics.supported) {
        final permission = HealthMetrics.permissionByMetric[metric];
        if (permission != null && grantedPermissions.contains(permission)) {
          grantedMetrics.add(metric);
        } else {
          missingMetrics.add(metric);
        }
      }

      final available = status == 'available';
      return Right(
        jsonEncode(<String, dynamic>{
          'provider': 'health_connect',
          'available': available,
          'status': status,
          'sdk_int': sdkInt,
          'granted_metrics': grantedMetrics,
          'missing_metrics': missingMetrics,
          'supported_metrics': HealthMetrics.supported,
          'next_step': _nextStepFor(status, missingMetrics),
        }),
      );
    } catch (e) {
      return Left(ServerFailure('health_status_failed: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> getHealthDataFormattedJson({
    required String metric,
    String? startDate,
    String? endDate,
  }) async {
    try {
      if (!HealthMetrics.isSupported(metric)) {
        return Left(
          ServerFailure(
            'health_unsupported_metric: $metric (supported: ${HealthMetrics.description})',
          ),
        );
      }

      final now = DateTime.now();
      final DateTime end;
      if (endDate != null) {
        final parsed = DateTime.tryParse(endDate);
        if (parsed == null) {
          return Left(
            ServerFailure(
              'health_invalid_range: unparsable endDate "$endDate"',
            ),
          );
        }
        end = parsed;
      } else {
        end = now;
      }

      final DateTime start;
      if (startDate != null) {
        final parsed = DateTime.tryParse(startDate);
        if (parsed == null) {
          return Left(
            ServerFailure(
              'health_invalid_range: unparsable startDate "$startDate"',
            ),
          );
        }
        start = parsed;
      } else {
        start = end.subtract(const Duration(hours: 24));
      }

      if (!start.isBefore(end)) {
        return Left(
          ServerFailure(
            'health_invalid_range: start "$startDate" must be before end "$endDate"',
          ),
        );
      }

      final availability = await _bounded(_platform.availability());
      if (availability == null || availability['status'] != 'available') {
        return const Left(
          ServerFailure(
            'health_unavailable: Health Connect is not available on this device',
          ),
        );
      }

      final permission = HealthMetrics.permissionByMetric[metric];
      final grantedPermissions = await _bounded(
        _platform.grantedPermissions(),
      );
      if (grantedPermissions == null) {
        return const Left(
          ServerFailure(
            'health_permission_denied: no response from Health Connect for granted permissions',
          ),
        );
      }
      if (permission == null || !grantedPermissions.contains(permission)) {
        return Left(
          ServerFailure(
            'health_permission_denied: grant $permission to read $metric in Health Connect',
          ),
        );
      }

      final result = await _bounded(
        _platform.readMetric(
          metric: metric,
          startTimeMs: start.millisecondsSinceEpoch,
          endTimeMs: end.millisecondsSinceEpoch,
        ),
      );
      if (result == null) {
        return Left(
          ServerFailure(
            'health_read_failed: no response from Health Connect for $metric',
          ),
        );
      }

      final rawRecords = (result['records'] as List?) ?? <dynamic>[];
      final truncated = rawRecords.length > 200;
      final records = truncated ? rawRecords.take(200).toList() : rawRecords;
      final summary =
          (result['summary'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      final startIso = (result['start'] as String?) ?? start.toIso8601String();
      final endIso = (result['end'] as String?) ?? end.toIso8601String();

      return Right(
        jsonEncode(<String, dynamic>{
          'metric': metric,
          'start': startIso,
          'end': endIso,
          'summary': summary,
          'records': records,
          'truncated': truncated,
        }),
      );
    } catch (e) {
      return Left(ServerFailure('health_read_failed: $e'));
    }
  }

  @override
  Future<bool> checkPermission() async {
    try {
      final availability = await _bounded(_platform.availability());
      if (availability == null || availability['status'] != 'available') {
        return false;
      }
      final grantedPermissions = await _bounded(
        _platform.grantedPermissions(),
      );
      if (grantedPermissions == null) {
        return false;
      }
      for (final metric in HealthMetrics.supported) {
        final permission = HealthMetrics.permissionByMetric[metric];
        if (permission != null && grantedPermissions.contains(permission)) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  String _nextStepFor(String status, List<String> missingMetrics) {
    if (status == 'available') {
      return missingMetrics.isEmpty
          ? ''
          : 'Grant health permissions in Health Connect';
    }
    return 'Install or update Health Connect';
  }
}
