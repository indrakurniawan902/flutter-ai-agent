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
    Duration? timeout,
    Duration? innerWindow,
    Duration? permissionTimeout,
  }) {
    return RegisteredTool(
      name: name,
      description: name,
      parameters: const {'type': 'object'},
      securityTier: tier,
      execute: execute,
      checkPermission: checkPermission,
      timeout: timeout,
      innerWindow: innerWindow,
      permissionTimeout: permissionTimeout,
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

  group('per-tool timeout override', () {
    test('bounds a never-completing executor with the override', () async {
      registry.register(
        tool(
          name: 'short_hang_tool',
          tier: SecurityTier.tier1Auto,
          timeout: const Duration(milliseconds: 200),
          execute: (_) => Completer<Either<Failure, String>>().future,
        ),
      );

      final stopwatch = Stopwatch()..start();
      final result = await registry.executeTool('short_hang_tool');
      stopwatch.stop();

      expect(result, isA<Left<Failure, String>>());
      expect(result.fold((failure) => failure, (_) => null),
          isA<ToolTimeoutFailure>());
      expect(
        result.fold((failure) => failure.message, (_) => ''),
        contains('within 0s'),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('bounds a never-completing permission check with the override',
        () async {
      registry.register(
        tool(
          name: 'short_hang_perm_tool',
          tier: SecurityTier.tier2Permission,
          timeout: const Duration(milliseconds: 200),
          checkPermission: () => Completer<bool>().future,
          execute: (_) async => const Right('should not run'),
        ),
      );

      final stopwatch = Stopwatch()..start();
      final result = await registry.executeTool('short_hang_perm_tool');
      stopwatch.stop();

      expect(result, isA<Left<Failure, String>>());
      expect(result.fold((failure) => failure, (_) => null),
          isA<ToolTimeoutFailure>());
      expect(
        result.fold((failure) => failure.message, (_) => ''),
        contains('within 0s'),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a tool finishing under the override is not cut off', () async {
      registry.register(
        tool(
          name: 'slow_but_ok_tool',
          tier: SecurityTier.tier1Auto,
          timeout: const Duration(seconds: 2),
          execute: (_) async {
            await Future<void>.delayed(const Duration(seconds: 1));
            return const Right('ok');
          },
        ),
      );

      final result = await registry.executeTool('slow_but_ok_tool');

      expect(result, const Right<Failure, String>('ok'));
    });

    test('a tool without an override keeps the registry default', () {
      registry.register(
        tool(
          name: 'default_bound_tool',
          tier: SecurityTier.tier1Auto,
          execute: (_) async => const Right('ok'),
        ),
      );

      expect(
        registry.getTool('default_bound_tool')!.effectiveTimeout,
        ToolRegistry.toolExecutionTimeout,
      );
    });

    test('the permission stage uses the permission bound, not the execution bound',
        () async {
      // A 25s execution window with a 200ms permission bound: if executeTool used
      // effectiveTimeout for the pre-check this would hang for 25s, so the elapsed
      // assertion below is what pins the call site.
      registry.register(
        tool(
          name: 'long_window_hang_perm_tool',
          tier: SecurityTier.tier2Permission,
          timeout: const Duration(seconds: 25),
          permissionTimeout: const Duration(milliseconds: 200),
          checkPermission: () => Completer<bool>().future,
          execute: (_) async => const Right('should not run'),
        ),
      );

      final stopwatch = Stopwatch()..start();
      final result = await registry.executeTool('long_window_hang_perm_tool');
      stopwatch.stop();

      expect(result, isA<Left<Failure, String>>());
      expect(result.fold((failure) => failure, (_) => null),
          isA<ToolTimeoutFailure>());
      expect(
        result.fold((failure) => failure.message, (_) => ''),
        contains('within 0s'),
      );
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });
}
