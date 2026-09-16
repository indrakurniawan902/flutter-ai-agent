import 'dart:io';

import 'package:flutter_ai_agent/domain/tools/chat/system_settings_allow_list.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('overlay bubble native wiring', () {
    late bool ready;
    late String manifest;
    late String activityKt;
    late String bubbleKt;
    late String serviceKt;

    setUpAll(() {
      final root = Directory.current.path;
      final manifestFile =
          File('$root/android/app/src/main/AndroidManifest.xml');
      final activityFile = File(
        '$root/android/app/src/main/kotlin/ai/hermes/flames/MainActivity.kt',
      );
      final bubbleFile = File(
        '$root/android/app/src/main/kotlin/ai/hermes/flames/FlamesOverlayBubble.kt',
      );
      final serviceFile = File(
        '$root/android/app/src/main/kotlin/ai/hermes/flames/FlamesBackgroundService.kt',
      );

      ready = manifestFile.existsSync() &&
          activityFile.existsSync() &&
          bubbleFile.existsSync() &&
          serviceFile.existsSync();
      if (!ready) {
        markTestSkipped('overlay bubble native files not found');
        return;
      }

      manifest = manifestFile.readAsStringSync();
      activityKt = activityFile.readAsStringSync();
      bubbleKt = bubbleFile.readAsStringSync();
      serviceKt = serviceFile.readAsStringSync();
    });

    test('manifest declares SYSTEM_ALERT_WINDOW without a uses-feature', () {
      if (!ready) return;

      expect(
        RegExp(
          r'<uses-permission\s+android:name="android\.permission\.SYSTEM_ALERT_WINDOW"\s*/>',
        ).hasMatch(manifest),
        isTrue,
      );
      expect(
        RegExp(r'<uses-feature[^>]*SYSTEM_ALERT_WINDOW').hasMatch(manifest),
        isFalse,
      );
    });

    test('MainActivity bridges the overlay bubble channel', () {
      if (!ready) return;

      expect(
        activityKt,
        contains('"ai.hermes.flames/overlay_bubble"'),
      );
      for (final method in const [
        '"isPermissionGranted"',
        '"requestPermission"',
        '"isBubbleVisible"',
        '"showBubble"',
        '"hideBubble"',
        '"setRecording"',
      ]) {
        expect(activityKt, contains(method));
      }
      expect(activityKt, contains('Settings.canDrawOverlays('));
      expect(
        activityKt,
        contains('Settings.ACTION_MANAGE_OVERLAY_PERMISSION'),
      );
    });

    test('overlay setting is declared and mapped to its ACTION', () {
      if (!ready) return;

      expect(SystemSettingsAllowList.values, contains('overlay'));
      expect(SystemSettingsAllowList.overlay, equals('overlay'));
      expect(
        RegExp(
          r'"overlay"\s*->\s*Settings\.ACTION_MANAGE_OVERLAY_PERMISSION',
        ).hasMatch(activityKt),
        isTrue,
      );
    });

    test('bubble is a resource-free programmatic overlay view', () {
      if (!ready) return;

      expect(bubbleKt, contains('object FlamesOverlayBubble'));
      expect(bubbleKt, contains('fun show('));
      expect(bubbleKt, contains('fun hide('));
      expect(bubbleKt, contains('fun isVisible()'));
      expect(bubbleKt, contains('fun setRecording('));
      expect(bubbleKt, contains('TYPE_APPLICATION_OVERLAY'));
      expect(bubbleKt, contains('FLAG_NOT_FOCUSABLE'));
      expect(bubbleKt, contains('Settings.canDrawOverlays('));
    });

    test('service owns the bubble lifecycle and both tap tokens', () {
      if (!ready) return;

      expect(serviceKt, contains('ACTION_SHOW_BUBBLE'));
      expect(serviceKt, contains('ACTION_HIDE_BUBBLE'));
      expect(serviceKt, contains('ACTION_CANCEL_VOICE'));
      expect(serviceKt, contains('FlamesOverlayBubble.show('));
      expect(serviceKt, contains('FlamesOverlayBubble.hide('));
      expect(serviceKt, contains('"voice_input"'));
      expect(serviceKt, contains('"cancel_voice"'));
    });

    test('service onDestroy removes the bubble', () {
      if (!ready) return;

      final anchor = serviceKt.indexOf('override fun onDestroy()');
      expect(anchor, isNot(-1), reason: 'onDestroy not found');
      final end = serviceKt.indexOf('\n    }', anchor);
      expect(end, isNot(-1), reason: 'onDestroy closing brace not found');
      final onDestroyBody = serviceKt.substring(anchor, end);
      expect(
        RegExp(r'FlamesOverlayBubble\.hide\(').hasMatch(onDestroyBody),
        isTrue,
      );
    });
  });
}
