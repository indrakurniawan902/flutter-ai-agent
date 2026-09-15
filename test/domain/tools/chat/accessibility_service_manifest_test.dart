import 'dart:io';

import 'package:flutter_ai_agent/domain/tools/chat/system_settings_allow_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('accessibility native wiring (read-only)', () {
    late bool ready;
    late String manifest;
    late String serviceConfig;
    late String serviceKt;
    late String activityKt;

    setUpAll(() {
      final root = Directory.current.path;
      final manifestFile =
          File('$root/android/app/src/main/AndroidManifest.xml');
      final configFile = File(
        '$root/android/app/src/main/res/xml/accessibility_service_config.xml',
      );
      final serviceFile = File(
        '$root/android/app/src/main/kotlin/ai/hermes/flames/FlamesAccessibilityService.kt',
      );
      final activityFile = File(
        '$root/android/app/src/main/kotlin/ai/hermes/flames/MainActivity.kt',
      );

      ready = manifestFile.existsSync() &&
          configFile.existsSync() &&
          serviceFile.existsSync() &&
          activityFile.existsSync();
      if (!ready) {
        markTestSkipped('accessibility native files not found');
        return;
      }

      manifest = manifestFile.readAsStringSync();
      serviceConfig = configFile.readAsStringSync();
      serviceKt = serviceFile.readAsStringSync();
      activityKt = activityFile.readAsStringSync();
    });

    String accessibilityServiceBlock() {
      final anchor = manifest.indexOf('.FlamesAccessibilityService');
      final open = manifest.lastIndexOf('<service', anchor);
      final close = manifest.indexOf('</service>', anchor);
      return manifest.substring(open, close);
    }

    test('manifest declares the bound accessibility service', () {
      if (!ready) return;

      final block = accessibilityServiceBlock();

      expect(block, contains('android:name=".FlamesAccessibilityService"'));
      expect(
        block,
        contains(
          'android:permission="android.permission.BIND_ACCESSIBILITY_SERVICE"',
        ),
      );
      expect(block, contains('android:exported="true"'));
      expect(
        RegExp(
          r'<action\s+android:name="android\.accessibilityservice\.AccessibilityService"\s*/>',
        ).hasMatch(block),
        isTrue,
      );
      expect(
        RegExp(
          r'<meta-data[^>]*android:name="android\.accessibilityservice"[^>]*'
          r'android:resource="@xml/accessibility_service_config"',
        ).hasMatch(block),
        isTrue,
      );
    });

    test('manifest does not install-grant BIND_ACCESSIBILITY_SERVICE', () {
      if (!ready) return;

      expect(
        RegExp(r'<uses-permission[^>]*BIND_ACCESSIBILITY_SERVICE')
            .hasMatch(manifest),
        isFalse,
      );
      expect(
        RegExp(r'<uses-feature[^>]*accessibility', caseSensitive: false)
            .hasMatch(manifest),
        isFalse,
      );
    });

    test('service config retrieves window content', () {
      if (!ready) return;

      expect(
        RegExp(r'<accessibility-service\b').hasMatch(serviceConfig),
        isTrue,
      );
      expect(
        RegExp(r'android:canRetrieveWindowContent="true"')
            .hasMatch(serviceConfig),
        isTrue,
      );
    });

    test('Kotlin service exposes liveness API and flat node keys', () {
      if (!ready) return;

      expect(
        serviceKt,
        contains('FlamesAccessibilityService : AccessibilityService'),
      );
      expect(serviceKt, contains('fun isConnected()'));
      expect(serviceKt, contains('fun isEnabledInSettings('));
      expect(serviceKt, contains('fun captureTree('));

      for (final key in const [
        'role',
        'text',
        'contentDescription',
        'packageName',
        'clickable',
        'focusable',
        'editable',
        'scrollable',
        'depth',
        'bounds',
      ]) {
        expect(serviceKt, contains('"$key"'), reason: 'missing node key $key');
      }
    });

    test('no screen-writing API ships in the service or the activity', () {
      if (!ready) return;

      for (final source in [serviceKt, activityKt]) {
        expect(source, isNot(contains('performAction')));
        expect(source, isNot(contains('dispatchGesture')));
        expect(source, isNot(contains('performGlobalAction')));
      }
    });

    test('captureTree skips password nodes before collecting them', () {
      if (!ready) return;

      expect(serviceKt, contains('isPassword'));
      expect(serviceKt, contains('continue'));

      final captureStart = serviceKt.indexOf('fun captureTree(');
      final captureEnd = serviceKt.indexOf('override fun onServiceConnected');
      expect(captureStart, greaterThanOrEqualTo(0));
      expect(captureEnd, greaterThan(captureStart));
      final captureBlock = serviceKt.substring(captureStart, captureEnd);

      expect(captureBlock, contains('node.isPassword'));
      final skipIndex = captureBlock.indexOf('node.isPassword');
      final appendIndex = captureBlock.indexOf('nodes.add(');
      expect(skipIndex, greaterThanOrEqualTo(0));
      expect(appendIndex, greaterThanOrEqualTo(0));
      expect(
        skipIndex,
        lessThan(appendIndex),
        reason: 'the password skip must happen before the node is serialized',
      );
    });

    test('MainActivity bridges the accessibility inspector channel', () {
      if (!ready) return;

      expect(
        activityKt,
        contains('"ai.hermes.flames/accessibility_inspector"'),
      );
      for (final method in const [
        '"isPermissionGranted"',
        '"isServiceConnected"',
        '"requestPermission"',
        '"getScreenTree"',
      ]) {
        expect(activityKt, contains(method));
      }
      expect(activityKt, contains('FlamesAccessibilityService.captureTree('));
    });

    test('accessibility setting is declared and mapped to its ACTION', () {
      if (!ready) return;

      expect(SystemSettingsAllowList.values, contains('accessibility'));
      expect(
        RegExp(
          r'"accessibility"\s*->\s*Settings\.ACTION_ACCESSIBILITY_SETTINGS',
        ).hasMatch(activityKt),
        isTrue,
      );
    });
  });
}
