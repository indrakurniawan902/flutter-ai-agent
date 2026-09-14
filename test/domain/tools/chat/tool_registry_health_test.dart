import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/health_metrics.dart';
import 'package:flutter_ai_agent/domain/tools/chat/health_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockHealthService extends Mock implements HealthServiceBase {}

void main() {
  late MockHealthService mockHealth;

  setUp(() {
    mockHealth = MockHealthService();
  });

  group('registerHealthTools', () {
    test('constructor registers health_status and get_health_data', () {
      final registry = ToolRegistry(healthService: mockHealth);

      expect(registry.hasTool('health_status'), isTrue);
      expect(registry.hasTool('get_health_data'), isTrue);
    });

    test('health_status is tier1 auto with a null checkPermission', () {
      final registry = ToolRegistry(healthService: mockHealth);
      final tool = registry.getTool('health_status')!;

      expect(tool.securityTier, SecurityTier.tier1Auto);
      expect(tool.checkPermission, isNull);
    });

    test('get_health_data is tier2 permission with a non-null checkPermission',
        () {
      final registry = ToolRegistry(healthService: mockHealth);
      final tool = registry.getTool('get_health_data')!;

      expect(tool.securityTier, SecurityTier.tier2Permission);
      expect(tool.checkPermission, isNotNull);
    });

    test('get_health_data schema enum equals HealthMetrics.supported', () {
      final registry = ToolRegistry(healthService: mockHealth);
      final params = registry.getTool('get_health_data')!.parameters;
      final metric = (params['properties'] as Map)['metric'] as Map;

      expect(metric['enum'], HealthMetrics.supported);
      expect(params['required'], ['metric']);
    });

    test('executeTool get_health_data delegates metric and range', () async {
      when(() => mockHealth.checkPermission()).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFormattedJson(
          metric: any(named: 'metric'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => const Right('{"metric":"steps"}'));

      final registry = ToolRegistry(healthService: mockHealth);
      final result = await registry.executeTool(
        'get_health_data',
        {'metric': 'steps'},
      );

      expect(result, const Right<Failure, String>('{"metric":"steps"}'));
      verify(
        () => mockHealth.getHealthDataFormattedJson(
          metric: 'steps',
          startDate: null,
          endDate: null,
        ),
      ).called(1);
    });

    test('executeTool health_status delegates status', () async {
      when(() => mockHealth.healthStatusFormattedJson())
          .thenAnswer((_) async => const Right('{"available":true}'));

      final registry = ToolRegistry(healthService: mockHealth);
      final result = await registry.executeTool('health_status');

      expect(result, const Right<Failure, String>('{"available":true}'));
      verify(() => mockHealth.healthStatusFormattedJson()).called(1);
    });

    test('permission denied returns PermissionFailure without reading',
        () async {
      when(() => mockHealth.checkPermission()).thenAnswer((_) async => false);

      final registry = ToolRegistry(healthService: mockHealth);
      final result = await registry.executeTool(
        'get_health_data',
        {'metric': 'steps'},
      );

      expect(
        result,
        const Left<Failure, String>(
          PermissionFailure('Permission denied for tool: get_health_data'),
        ),
      );
      verifyNever(
        () => mockHealth.getHealthDataFormattedJson(
          metric: any(named: 'metric'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      );
    });

    test('when checkPermission returns true the service Right is returned',
        () async {
      when(() => mockHealth.checkPermission()).thenAnswer((_) async => true);
      when(
        () => mockHealth.getHealthDataFormattedJson(
          metric: any(named: 'metric'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
        ),
      ).thenAnswer((_) async => const Right('{"granted":true}'));

      final registry = ToolRegistry(healthService: mockHealth);
      final result = await registry.executeTool(
        'get_health_data',
        {'metric': 'steps'},
      );

      expect(result, const Right<Failure, String>('{"granted":true}'));
    });

    test('when no HealthServiceBase is injected neither tool is registered',
        () {
      final registry = ToolRegistry();

      expect(registry.hasTool('health_status'), isFalse);
      expect(registry.hasTool('get_health_data'), isFalse);
    });
  });
}
