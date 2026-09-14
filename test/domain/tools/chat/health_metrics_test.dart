import 'dart:io';

import 'package:flutter_ai_agent/domain/tools/chat/health_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HealthMetrics <-> Kotlin permissionFor drift guard', () {
    late String kotlinFile;

    setUpAll(() {
      final projectRoot = Directory.current;
      final kotlinPath = File(
        '${projectRoot.path}/android/app/src/main/kotlin/ai/hermes/flames/FlamesHealthConnect.kt',
      );
      if (!kotlinPath.existsSync()) {
        markTestSkipped('Kotlin FlamesHealthConnect.kt not found');
        return;
      }
      kotlinFile = kotlinPath.readAsStringSync();
    });

    /// Extracts the `when (metric) { ... }` block inside the
    /// `permissionFor(metric: String)` function and parses every
    /// `"<metric>" -> HealthPermission.getReadPermission(...)` arm into a set
    /// of metric ids. The `else -> null` arm is ignored.
    Set<String> parseKotlinPermissionFor(String source) {
      final fnIdx = source.indexOf('fun permissionFor(metric: String)');
      if (fnIdx == -1) {
        fail('Could not find `fun permissionFor(metric: String)`');
      }

      final whenIdx = source.indexOf('when (metric)', fnIdx);
      if (whenIdx == -1) {
        fail('Could not find `when (metric)` inside permissionFor');
      }

      final braceIdx = source.indexOf('{', whenIdx);
      if (braceIdx == -1) {
        fail('Could not find opening brace of `when (metric)` block');
      }

      int depth = 0;
      int endIdx = -1;
      for (int i = braceIdx; i < source.length; i++) {
        if (source[i] == '{') depth++;
        if (source[i] == '}') {
          depth--;
          if (depth == 0) {
            endIdx = i;
            break;
          }
        }
      }
      if (endIdx == -1) {
        fail('Could not find matching closing brace for `when (metric)` block');
      }

      final whenBlock = source.substring(braceIdx + 1, endIdx);
      final regex = RegExp(
        r'"([^"]+)"\s*->\s*HealthPermission\.getReadPermission\(',
      );

      return <String>{
        for (final m in regex.allMatches(whenBlock)) m.group(1)!.trim(),
      };
    }

    test('Dart supported metrics match Kotlin permissionFor arms exactly', () {
      if (kotlinFile.isEmpty) return; // setUpAll marked skipped

      final kotlinMetrics = parseKotlinPermissionFor(kotlinFile);

      expect(
        HealthMetrics.supported.toSet(),
        equals(kotlinMetrics),
        reason: '''
Dart and Kotlin health metric ids have drifted!

Dart (HealthMetrics.supported): ${HealthMetrics.supported.join(', ')}
Kotlin (parsed from FlamesHealthConnect.kt): ${kotlinMetrics.toList()..sort()}

To fix:
- If a metric is in Dart but not Kotlin: add the corresponding
  `"<metric>" -> HealthPermission.getReadPermission(...)` arm in
  FlamesHealthConnect.kt.
- If a metric is in Kotlin but not Dart: add the constant to HealthMetrics
  in lib/domain/tools/chat/health_metrics.dart.

The drift test is the source of truth for keeping them in sync.
''',
      );
    });

    // Proves the parser above is a real guard: if the Kotlin `when` gains an arm
    // the Dart list does not have (or vice versa) the parsed sets must differ.
    test('parser detects a synthetic drift in the Kotlin when-block', () {
      const driftedKotlin = '''
        fun permissionFor(metric: String): String? = when (metric) {
            "steps" -> HealthPermission.getReadPermission(StepsRecord::class)
            "heart_rate" -> HealthPermission.getReadPermission(HeartRateRecord::class)
            "brand_new_metric" -> HealthPermission.getReadPermission(NewRecord::class)
            else -> null
        }
      ''';

      final parsed = parseKotlinPermissionFor(driftedKotlin);

      expect(parsed, <String>{'steps', 'heart_rate', 'brand_new_metric'});
      expect(parsed, isNot(equals(HealthMetrics.supported.toSet())));
    });

    test('supported metrics contain no duplicates', () {
      expect(
        HealthMetrics.supported.length,
        equals(HealthMetrics.supported.toSet().length),
        reason: 'HealthMetrics.supported contains duplicates',
      );
    });

    test('every supported metric has a permissionByMetric entry', () {
      for (final metric in HealthMetrics.supported) {
        expect(
          HealthMetrics.permissionByMetric.containsKey(metric),
          isTrue,
          reason: 'Missing permissionByMetric entry for $metric',
        );
      }
    });

    test('every permission string is a valid Health Connect read permission',
        () {
      final pattern = RegExp(r'^android\.permission\.health\.READ_[A-Z_]+$');
      for (final permission in HealthMetrics.permissionByMetric.values) {
        expect(
          pattern.hasMatch(permission),
          isTrue,
          reason: 'Invalid health permission string: $permission',
        );
      }
    });
  });
}
