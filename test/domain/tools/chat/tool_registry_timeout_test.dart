import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late ToolRegistry registry;

  setUp(() {
    registry = ToolRegistry();
  });

  RegisteredTool tool({
    required String name,
    required SecurityTier tier,
    required ToolExecutor execute,
    PermissionChecker? checkPermission,
  }) {
    return RegisteredTool(
      name: name,
      description: name,
      parameters: const {'type': 'object'},
      securityTier: tier,
      execute: execute,
      checkPermission: checkPermission,
    );
  }

  group('ToolRegistry.executeTool timeout bound', () {
    test('bounds a never-completing executor', () async {
      registry.register(
        tool(
          name: 'hang_tool',
          tier: SecurityTier.tier1Auto,
          execute: (_) => Completer<Either<Failure, String>>().future,
        ),
      );

      final stopwatch = Stopwatch()..start();
      final result = await registry.executeTool('hang_tool');
      stopwatch.stop();

      expect(result.isLeft(), isTrue);
      expect(
        result.fold((failure) => failure.message, (_) => ''),
        contains('tool_timeout'),
      );
      expect(result.fold((failure) => failure, (_) => null),
          isA<ToolTimeoutFailure>());
      expect(
        stopwatch.elapsed,
        lessThan(ToolRegistry.toolExecutionTimeout * 2),
      );
    });

    test('bounds a never-completing permission check', () async {
      registry.register(
        tool(
          name: 'hang_perm_tool',
          tier: SecurityTier.tier2Permission,
          checkPermission: () => Completer<bool>().future,
          execute: (_) async => const Right('should not run'),
        ),
      );

      final stopwatch = Stopwatch()..start();
      final result = await registry.executeTool('hang_perm_tool');
      stopwatch.stop();

      expect(result.isLeft(), isTrue);
      expect(
        result.fold((failure) => failure.message, (_) => ''),
        contains('tool_timeout'),
      );
      expect(
        result.fold((failure) => failure.message, (_) => ''),
        contains('hang_perm_tool'),
      );
      expect(
        stopwatch.elapsed,
        lessThan(ToolRegistry.toolExecutionTimeout * 2),
      );
    });

    test('a fast tool is unaffected', () async {
      registry.register(
        tool(
          name: 'fast_tool',
          tier: SecurityTier.tier1Auto,
          execute: (_) async => const Right('ok'),
        ),
      );

      final result = await registry.executeTool('fast_tool');

      expect(result, const Right<Failure, String>('ok'));
    });
  });
}
