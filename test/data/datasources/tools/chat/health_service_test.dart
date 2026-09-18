import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/health_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/health_metrics.dart';
import 'package:flutter_ai_agent/domain/tools/chat/health_service.dart';
import 'package:flutter_test/flutter_test.dart';

class HangingHealthPlatform implements HealthPlatformWrapper {
  bool hangAvailability = false;
  bool hangGranted = false;
  bool hangRead = false;

  @override
  Future<Map<String, dynamic>?> availability() {
    if (hangAvailability) return Completer<Map<String, dynamic>?>().future;
    return Future<Map<String, dynamic>?>.value(<String, dynamic>{
      'status': 'available',
      'sdk_int': 34,
      'provider_installed': true,
    });
  }

  @override
  Future<List<String>> grantedPermissions() {
    if (hangGranted) return Completer<List<String>>().future;
    return Future<List<String>>.value(_allPermissions());
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<Map<String, dynamic>?> readMetric({
    required String metric,
    required int startTimeMs,
    required int endTimeMs,
  }) {
    if (hangRead) return Completer<Map<String, dynamic>?>().future;
    return Future<Map<String, dynamic>?>.value(<String, dynamic>{
      'metric': metric,
      'records': <dynamic>[],
      'summary': <String, dynamic>{},
    });
  }
}

class FakeHealthPlatform implements HealthPlatformWrapper {
  Map<String, dynamic>? availabilityResult = <String, dynamic>{
    'status': 'available',
    'sdk_int': 34,
    'provider_installed': true,
  };
  List<String> granted = <String>[];
  Map<String, dynamic>? readResult;
  bool throwOnAvailability = false;
  bool throwOnGranted = false;
  bool throwOnRead = false;

  @override
  Future<Map<String, dynamic>?> availability() async {
    if (throwOnAvailability) {
      throw PlatformException(code: 'boom', message: 'availability failed');
    }
    return availabilityResult;
  }

  @override
  Future<List<String>> grantedPermissions() async {
    if (throwOnGranted) {
      throw PlatformException(code: 'boom', message: 'granted failed');
    }
    return granted;
  }

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<Map<String, dynamic>?> readMetric({
    required String metric,
    required int startTimeMs,
    required int endTimeMs,
  }) async {
    if (throwOnRead) {
      throw PlatformException(code: 'boom', message: 'read failed');
    }
    return readResult;
  }
}

List<String> _allPermissions() => HealthMetrics.supported
    .map((metric) => HealthMetrics.permissionByMetric[metric]!)
    .toList();

Map<String, dynamic> _decode(Either<Failure, String> result) {
  final raw = result.getOrElse(() => '');
  return jsonDecode(raw) as Map<String, dynamic>;
}

Failure _failure(Either<Failure, String> result) =>
    result.fold((failure) => failure, (_) => fail('Expected Left'));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeHealthPlatform platform;
  late HealthService service;

  setUp(() {
    platform = FakeHealthPlatform()..granted = _allPermissions();
    service = HealthService(platform: platform);
  });

  group('getHealthDataFormattedJson metric mapping', () {
    test('steps maps summary.total and records', () async {
      platform.readResult = <String, dynamic>{
        'metric': 'steps',
        'start': '2026-09-12T00:00:00.000Z',
        'end': '2026-09-13T00:00:00.000Z',
        'records': <dynamic>[
          <String, dynamic>{
            'start': '2026-09-12T08:00:00.000Z',
            'end': '2026-09-12T09:00:00.000Z',
            'count': 1200,
          },
        ],
        'summary': <String, dynamic>{'total': 1200},
      };

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
      );

      expect(result.isRight(), isTrue);
      final decoded = _decode(result);
      expect(decoded['metric'], 'steps');
      expect((decoded['summary'] as Map)['total'], 1200);
      expect(decoded['truncated'], isFalse);
      expect(decoded['records'], hasLength(1));
    });

    test('heart_rate maps min/max/avg/samples', () async {
      platform.readResult = <String, dynamic>{
        'metric': 'heart_rate',
        'start': '2026-09-12T00:00:00.000Z',
        'end': '2026-09-13T00:00:00.000Z',
        'records': <dynamic>[
          <String, dynamic>{'time': '2026-09-12T08:00:00.000Z', 'bpm': 72},
        ],
        'summary': <String, dynamic>{
          'min': 60,
          'max': 140,
          'avg': 78.5,
          'samples': 42,
        },
      };

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.heartRate,
      );

      expect(result.isRight(), isTrue);
      final summary = _decode(result)['summary'] as Map;
      expect(summary['min'], 60);
      expect(summary['max'], 140);
      expect(summary['avg'], 78.5);
      expect(summary['samples'], 42);
    });

    test('sleep maps sessions, total_minutes and nested stages', () async {
      platform.readResult = <String, dynamic>{
        'metric': 'sleep',
        'start': '2026-09-12T00:00:00.000Z',
        'end': '2026-09-13T00:00:00.000Z',
        'records': <dynamic>[
          <String, dynamic>{
            'start': '2026-09-12T23:00:00.000Z',
            'end': '2026-09-13T07:00:00.000Z',
            'duration_minutes': 480,
            'stages': <dynamic>[
              <String, dynamic>{
                'stage': 'deep',
                'start': '2026-09-12T23:00:00.000Z',
                'end': '2026-09-13T00:30:00.000Z',
              },
              <String, dynamic>{
                'stage': 'rem',
                'start': '2026-09-13T00:30:00.000Z',
                'end': '2026-09-13T02:00:00.000Z',
              },
            ],
          },
        ],
        'summary': <String, dynamic>{'sessions': 1, 'total_minutes': 480},
      };

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.sleep,
      );

      expect(result.isRight(), isTrue);
      final decoded = _decode(result);
      final summary = decoded['summary'] as Map;
      expect(summary['sessions'], 1);
      expect(summary['total_minutes'], 480);
      final records = decoded['records'] as List;
      final stages = (records.single as Map)['stages'] as List;
      expect(stages, hasLength(2));
      expect((stages.first as Map)['stage'], 'deep');
    });

    test('caps records at 200 and marks truncated', () async {
      platform.readResult = <String, dynamic>{
        'metric': 'heart_rate',
        'start': '2026-09-12T00:00:00.000Z',
        'end': '2026-09-13T00:00:00.000Z',
        'records': List<dynamic>.generate(
          205,
          (index) => <String, dynamic>{'time': 't$index', 'bpm': 70},
        ),
        'summary': <String, dynamic>{'samples': 205},
      };

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.heartRate,
      );

      expect(result.isRight(), isTrue);
      final decoded = _decode(result);
      expect(decoded['truncated'], isTrue);
      expect(decoded['records'], hasLength(200));
    });
  });

  group('getHealthDataFormattedJson validation', () {
    test('unsupported metric returns health_unsupported_metric', () async {
      final result = await service.getHealthDataFormattedJson(
        metric: 'blood_pressure',
      );

      expect(result.isLeft(), isTrue);
      expect(_failure(result).message, startsWith('health_unsupported_metric'));
    });

    test('unparsable startDate returns health_invalid_range', () async {
      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
        startDate: 'not-a-date',
      );

      expect(result.isLeft(), isTrue);
      expect(_failure(result).message, contains('health_invalid_range'));
    });

    test('unparsable endDate returns health_invalid_range', () async {
      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
        endDate: 'nope',
      );

      expect(result.isLeft(), isTrue);
      expect(_failure(result).message, contains('health_invalid_range'));
    });

    test('start not before end returns health_invalid_range', () async {
      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
        startDate: '2026-09-13T00:00:00.000Z',
        endDate: '2026-09-12T00:00:00.000Z',
      );

      expect(result.isLeft(), isTrue);
      expect(_failure(result).message, contains('health_invalid_range'));
    });
  });

  group('healthStatusFormattedJson', () {
    test('unavailable status returns available false with next_step', () async {
      platform.availabilityResult = <String, dynamic>{
        'status': 'unavailable',
        'sdk_int': 28,
        'provider_installed': false,
      };

      final result = await service.healthStatusFormattedJson();

      expect(result.isRight(), isTrue);
      final decoded = _decode(result);
      expect(decoded['available'], isFalse);
      expect(decoded['status'], 'unavailable');
      expect((decoded['next_step'] as String).isNotEmpty, isTrue);
    });

    test('available status lists granted and missing metrics', () async {
      platform.granted = <String>[
        HealthMetrics.permissionByMetric[HealthMetrics.steps]!,
        HealthMetrics.permissionByMetric[HealthMetrics.weight]!,
      ];

      final result = await service.healthStatusFormattedJson();

      expect(result.isRight(), isTrue);
      final decoded = _decode(result);
      expect(decoded['available'], isTrue);
      expect(decoded['granted_metrics'], <String>['steps', 'weight']);
      expect((decoded['missing_metrics'] as List), contains('heart_rate'));
      expect((decoded['next_step'] as String).isNotEmpty, isTrue);
    });

    test('null availability returns health_unavailable', () async {
      platform.availabilityResult = null;

      final result = await service.healthStatusFormattedJson();

      expect(result.isLeft(), isTrue);
      expect(_failure(result).message, startsWith('health_unavailable'));
    });
  });

  group('getHealthDataFormattedJson platform failures', () {
    test('unavailable provider returns health_unavailable', () async {
      platform.availabilityResult = <String, dynamic>{'status': 'unavailable'};

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
      );

      expect(result.isLeft(), isTrue);
      expect(_failure(result).message, startsWith('health_unavailable'));
    });

    test('missing permission returns health_permission_denied', () async {
      platform.granted = <String>[];

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
      );

      expect(result.isLeft(), isTrue);
      expect(_failure(result).message, startsWith('health_permission_denied'));
    });

    test('null read result returns health_read_failed', () async {
      platform.readResult = null;

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
      );

      expect(result.isLeft(), isTrue);
      expect(_failure(result).message, startsWith('health_read_failed'));
    });
  });

  group('getHealthDataFormattedJson surfaced platform errors', () {
    test('platform error map surfaces error_code and real message', () async {
      platform.readResult = <String, dynamic>{
        'error_code': 'health_platform_error',
        'error_message': 'IllegalArgumentException: bad record',
      };

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
      );

      expect(result.isLeft(), isTrue);
      final message = _failure(result).message;
      expect(message, contains('health_platform_error'));
      expect(message, contains('IllegalArgumentException'));
      expect(message, isNot(contains('no response from Health Connect')));
    });

    test('timeout error map surfaces health_timeout, not blanket text',
        () async {
      platform.readResult = <String, dynamic>{
        'error_code': 'health_timeout',
        'error_message': 'no response from the platform within 5s',
      };

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
      );

      expect(result.isLeft(), isTrue);
      final message = _failure(result).message;
      expect(message, contains('health_timeout'));
      expect(message, isNot(contains('no response from Health Connect')));
    });

    test('summary survives when records are unavailable', () async {
      platform.readResult = <String, dynamic>{
        'metric': 'steps',
        'start': '2026-09-12T00:00:00.000Z',
        'end': '2026-09-13T00:00:00.000Z',
        'summary': <String, dynamic>{'total': 1200},
        'records': <dynamic>[],
        'records_unavailable': true,
        'records_error': 'IllegalArgumentException: x',
      };

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
      );

      expect(result.isRight(), isTrue);
      final decoded = _decode(result);
      expect((decoded['summary'] as Map)['total'], 1200);
      expect(decoded['records'], isEmpty);
      expect(decoded['records_unavailable'], isTrue);
      expect(decoded['records_error'], 'IllegalArgumentException: x');
    });

    test('a clean success payload keeps its exact shape', () async {
      platform.readResult = <String, dynamic>{
        'metric': 'steps',
        'start': '2026-09-12T00:00:00.000Z',
        'end': '2026-09-13T00:00:00.000Z',
        'summary': <String, dynamic>{'total': 1200},
        'records': <dynamic>[],
      };

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
      );

      expect(result.isRight(), isTrue);
      final decoded = _decode(result);
      expect(decoded['metric'], 'steps');
      expect(decoded['start'], '2026-09-12T00:00:00.000Z');
      expect(decoded['end'], '2026-09-13T00:00:00.000Z');
      expect(decoded['summary'], <String, dynamic>{'total': 1200});
      expect(decoded['records'], isEmpty);
      expect(decoded['truncated'], isFalse);
      expect(decoded.containsKey('records_unavailable'), isFalse);
    });
  });

  group('wrapper exceptions never escape', () {
    test('availability throw -> healthStatusFormattedJson Left', () async {
      platform.throwOnAvailability = true;

      final result = await service.healthStatusFormattedJson();

      expect(result.isLeft(), isTrue);
    });

    test(
      'grantedPermissions throw -> healthStatusFormattedJson Left',
      () async {
        platform.throwOnGranted = true;

        final result = await service.healthStatusFormattedJson();

        expect(result.isLeft(), isTrue);
      },
    );

    test('availability throw -> getHealthDataFormattedJson Left', () async {
      platform.throwOnAvailability = true;

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
      );

      expect(result.isLeft(), isTrue);
    });

    test('readMetric throw -> getHealthDataFormattedJson Left', () async {
      platform.throwOnRead = true;

      final result = await service.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
      );

      expect(result.isLeft(), isTrue);
    });

    test('throw on availability -> checkPermission false', () async {
      platform.throwOnAvailability = true;

      expect(await service.checkPermission(), isFalse);
    });

    test('throw on grantedPermissions -> checkPermission false', () async {
      platform.throwOnGranted = true;

      expect(await service.checkPermission(), isFalse);
    });
  });

  group('silent platform calls settle as structured failures', () {
    test('never-completing readMetric returns Left, does not hang', () async {
      final hanging = HangingHealthPlatform()..hangRead = true;
      final hangingService = HealthService(platform: hanging);

      final stopwatch = Stopwatch()..start();
      final result = await hangingService.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
      );
      stopwatch.stop();

      expect(result.isLeft(), isTrue);
      expect(_failure(result).message, contains('health_read_failed'));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 30)));
    });

    test('never-completing availability returns Left, does not hang', () async {
      final hanging = HangingHealthPlatform()..hangAvailability = true;
      final hangingService = HealthService(platform: hanging);

      final stopwatch = Stopwatch()..start();
      final result = await hangingService.getHealthDataFormattedJson(
        metric: HealthMetrics.steps,
      );
      stopwatch.stop();

      expect(result.isLeft(), isTrue);
      expect(_failure(result).message, contains('health_unavailable'));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 30)));
    });

    test('never-completing availability returns Left from healthStatus', () async {
      final hanging = HangingHealthPlatform()..hangAvailability = true;
      final hangingService = HealthService(platform: hanging);

      final result = await hangingService.healthStatusFormattedJson();

      expect(result.isLeft(), isTrue);
      expect(_failure(result).message, contains('health_unavailable'));
    });

    test('never-completing grantedPermissions returns Left from healthStatus',
        () async {
      final hanging = HangingHealthPlatform()..hangGranted = true;
      final hangingService = HealthService(platform: hanging);

      final result = await hangingService.healthStatusFormattedJson();

      expect(result.isLeft(), isTrue);
    });

    test('never-completing availability returns checkPermission false',
        () async {
      final hanging = HangingHealthPlatform()..hangAvailability = true;
      final hangingService = HealthService(platform: hanging);

      expect(await hangingService.checkPermission(), isFalse);
    });
  });

  group('checkPermission', () {
    test('true when available and at least one permission granted', () async {
      platform.granted = <String>[
        HealthMetrics.permissionByMetric[HealthMetrics.steps]!,
      ];

      expect(await service.checkPermission(), isTrue);
    });

    test('false when no permission is granted', () async {
      platform.granted = <String>[];

      expect(await service.checkPermission(), isFalse);
    });

    test('false when provider is not available', () async {
      platform.availabilityResult = <String, dynamic>{'status': 'unavailable'};

      expect(await service.checkPermission(), isFalse);
    });
  });

  group('declared window constants', () {
    test('health status window is 13s and health read window is 19s', () {
      expect(kHealthStatusWindow, const Duration(seconds: 13));
      expect(kHealthReadWindow, const Duration(seconds: 19));
    });
  });
}
