import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/domain/tools/chat/system_settings_allow_list.dart';

void main() {
  group('SystemSettingsAllowList <-> Kotlin MainActivity drift guard', () {
    late String kotlinFile;

    setUpAll(() {
      final projectRoot = Directory.current;
      final kotlinPath = File(
        '${projectRoot.path}/android/app/src/main/kotlin/ai/hermes/flames/MainActivity.kt',
      );
      if (!kotlinPath.existsSync()) {
        markTestSkipped('Kotlin MainActivity.kt not found');
        return;
      }
      kotlinFile = kotlinPath.readAsStringSync();
    });

    /// Extracts the `when (type) { ... }` block inside the `openSystemSettings`
    /// handler, and parses every `"<key>" -> Settings.ACTION_*` arm into a set
    /// of allowed keys (lowercase, trimmed). The `else -> null` arm is ignored.
    Set<String> parseKotlinAllowList(String source) {
      // Find the openSystemSettings handler's when block
      final openSettingsIdx = source.indexOf('"openSystemSettings"');
      if (openSettingsIdx == -1) {
        fail('Could not find "openSystemSettings" handler in MainActivity.kt');
      }

      // Find the `val action: String? = when (type) {` line after that
      final whenIdx = source.indexOf('when (type)', openSettingsIdx);
      if (whenIdx == -1) {
        fail('Could not find `when (type)` inside openSystemSettings handler');
      }

      // Find the opening brace of the when block
      final braceIdx = source.indexOf('{', whenIdx);
      if (braceIdx == -1) {
        fail('Could not find opening brace of `when (type)` block');
      }

      // Walk forward to find the matching closing brace (simple brace counter)
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
        fail('Could not find matching closing brace for `when (type)` block');
      }

      final whenBlock = source.substring(braceIdx + 1, endIdx);

      // Extract each `"key" -> Settings.ACTION_*` arm
      // Pattern: "key" -> Settings.ACTION_... (may have trailing comma or nothing)
      final regex = RegExp(r'"([^"]+)"\s*->\s*Settings\.ACTION_[A-Z0-9_]+');
      final matches = regex.allMatches(whenBlock);

      return <String>{
        for (final m in matches) m.group(1)!.toLowerCase().trim(),
      };
    }

    test('Dart allow-list values match Kotlin allow-list exactly', () {
      if (kotlinFile.isEmpty) return; // setUpAll marked skipped

      final dartKeys = SystemSettingsAllowList.set;
      final kotlinKeys = parseKotlinAllowList(kotlinFile);

      expect(
        dartKeys,
        equals(kotlinKeys),
        reason: '''
Dart and Kotlin allow-lists have drifted!

Dart (SystemSettingsAllowList.values): ${SystemSettingsAllowList.values.join(', ')}
Kotlin (parsed from MainActivity.kt): ${kotlinKeys.toList()..sort()}

To fix:
- If a value is in Dart but not Kotlin: add the corresponding
  `"<value>" -> Settings.ACTION_...` arm in MainActivity.kt.
- If a value is in Kotlin but not Dart: add the constant to
  SystemSettingsAllowList in lib/domain/tools/chat/system_settings_allow_list.dart.

The drift test is the source of truth for keeping them in sync.
''',
      );
    });

    test('Dart values are in a stable, declared order (no duplicates)', () {
      final values = SystemSettingsAllowList.values;
      final unique = values.toSet();
      expect(values.length, equals(unique.length),
          reason: 'SystemSettingsAllowList.values contains duplicates');
    });

    test('Dart description string is non-empty and comma-separated', () {
      final desc = SystemSettingsAllowList.description;
      expect(desc, isNotEmpty);
      expect(desc.contains(','), isTrue);
    });

    // Proves the parser above is a real guard: if the Kotlin `when` gains an arm
    // the Dart list does not have (or vice versa) the parsed sets must differ.
    test('parser detects a synthetic drift in the Kotlin when-block', () {
      const driftedKotlin = '''
        when (call.method) {
            "openSystemSettings" -> {
                val type = call.argument<String>("type")
                val action: String? = when (type) {
                    "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
                    "wifi" -> Settings.ACTION_WIFI_SETTINGS
                    "nfc" -> Settings.ACTION_NFC_SETTINGS
                    "brand_new_page" -> Settings.ACTION_SOMETHING_NEW
                    else -> null
                }
            }
            else -> result.notImplemented()
        }
      ''';

      final parsed = parseKotlinAllowList(driftedKotlin);

      expect(parsed, <String>{'bluetooth', 'wifi', 'nfc', 'brand_new_page'});
      expect(parsed, isNot(equals(SystemSettingsAllowList.set)));
    });

    test('parser only reads the openSystemSettings handler, not other whens', () {
      const twoHandlers = '''
        when (call.method) {
            "requestPermission" -> {
                val action = when (mode) {
                    "unrelated" -> Settings.ACTION_SOMETHING_ELSE
                    else -> null
                }
            }
            "openSystemSettings" -> {
                val type = call.argument<String>("type")
                val action: String? = when (type) {
                    "bluetooth" -> Settings.ACTION_BLUETOOTH_SETTINGS
                    else -> null
                }
            }
        }
      ''';

      expect(parseKotlinAllowList(twoHandlers), <String>{'bluetooth'});
    });
  });
}