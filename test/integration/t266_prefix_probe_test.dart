// T26.6 pre-fix probe.
//
// This file deliberately avoids the post-fix constants (kWebReadTimeout,
// kHealthStatusWindow, kHealthReadWindow, kLocationToolWindow) so that it
// COMPILES against both the pre-fix tree and the post-fix tree. That is what
// makes it an assertion-level proof instead of a compile error.
//
// Run against the pre-fix tree it must fail on the "innerWindow isNotNull"
// assertion for read_web_page, health_status, get_health_data and get_location:
// each had a service-side window longer than its 10s registry default, so the
// registry's outer bound fired first and the tool's own honest error was
// unreachable. Against the fixed tree it passes.
//
// Do not delete this file: it is the proof that this class of bug cannot come
// back silently.
library;

import 'package:flutter_ai_agent/domain/tools/chat/health_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../helpers/mocks.dart';

class _MockHealthService extends Mock implements HealthServiceBase {}

void main() {
  group('T26.6 pre-fix probe: every service-side window declares its inner '
      'window', () {
    late ToolRegistry registry;

    setUp(() {
      registry = ToolRegistry(
        urlReaderService: MockUrlReaderService(),
        healthService: _MockHealthService(),
        locationService: MockLocationService(),
      );
    });

    const configurableWindowTools = <String>[
      'read_web_page',
      'health_status',
      'get_health_data',
      'get_location',
    ];

    for (final name in configurableWindowTools) {
      test('$name declares an inner window and is not on the 10s default', () {
        final tool = registry.getTool(name);
        expect(tool, isNotNull, reason: '$name must be registered');

        expect(
          tool!.innerWindow,
          isNotNull,
          reason:
              '$name: an undeclared inner window means the registry\'s outer '
              'bound fires first and the tool\'s own honest error is '
              'unreachable',
        );
        expect(
          tool.effectiveTimeout > ToolRegistry.toolExecutionTimeout,
          isTrue,
          reason:
              '$name: effectiveTimeout ${tool.effectiveTimeout} must be greater '
              'than the 10s default bound, so the tool must not be left on the '
              'default bound',
        );
        expect(
          tool.effectiveTimeout < const Duration(seconds: 30),
          isTrue,
          reason:
              '$name: effectiveTimeout ${tool.effectiveTimeout} must stay under '
              'the device bridge 30s call budget',
        );
      });
    }
  });
}
