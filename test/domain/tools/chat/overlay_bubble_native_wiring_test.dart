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

    test('bubble show wires tap and long-press callbacks', () {
      if (!ready) return;

      expect(
        bubbleKt,
        contains(
          'fun show(context: Context, onTap: () -> Unit, onLongPress: () -> Unit)',
        ),
      );
      expect(
        serviceKt,
        contains(
          'FlamesOverlayBubble.show(this, { handleBubbleTap() }, { handleBubbleLongPress() })',
        ),
      );

      final anchor = bubbleKt.indexOf('MotionEvent.ACTION_UP ->');
      expect(anchor, isNot(-1), reason: 'ACTION_UP branch not found');
      final end = bubbleKt.indexOf('\n                    }', anchor);
      expect(end, isNot(-1), reason: 'ACTION_UP closing brace not found');
      final body = bubbleKt.substring(anchor, end);

      expect(body, contains('LONG_PRESS_MIN_DURATION_MS'));
      expect(body, isNot(contains('TAP_MAX_DURATION_MS')));
      expect(
        body.indexOf('onTap()'),
        lessThan(body.indexOf('onLongPress()')),
        reason: 'tap must be the below-threshold branch',
      );
      expect(body, contains('snapToEdge('));
      expect(
        bubbleKt,
        contains('private const val LONG_PRESS_MIN_DURATION_MS = 500L'),
      );
    });

    test('bubble tap opens the app without touching voice state', () {
      if (!ready) return;

      final anchor = serviceKt.indexOf('private fun handleBubbleTap()');
      expect(anchor, isNot(-1), reason: 'handleBubbleTap not found');
      final end = serviceKt.indexOf('\n    }', anchor);
      expect(end, isNot(-1), reason: 'handleBubbleTap closing brace not found');
      final body = serviceKt.substring(anchor, end);

      expect(body, contains('launchApp('));
      expect(body, isNot(contains('setRecording(')));
      expect(body, isNot(contains('voice_input')));
      expect(body, isNot(contains('cancel_voice')));
      expect(body, isNot(contains('bubbleRecording')));
    });

    test('long-press keeps the voice tokens', () {
      if (!ready) return;

      final anchor = serviceKt.indexOf('private fun handleBubbleLongPress()');
      expect(anchor, isNot(-1), reason: 'handleBubbleLongPress not found');
      final end = serviceKt.indexOf('\n    }', anchor);
      expect(
        end,
        isNot(-1),
        reason: 'handleBubbleLongPress closing brace not found',
      );
      final body = serviceKt.substring(anchor, end);

      expect(body, contains('"voice_input"'));
      expect(body, contains('"cancel_voice"'));
      expect(body, contains('setRecording('));
      expect(body, contains('bubbleRecording'));
    });

    test('service launches MainActivity with task reuse flags', () {
      if (!ready) return;

      expect(
        serviceKt,
        contains(
          'const val ACTION_OPEN_APP = "ai.hermes.flames.action.OPEN_APP"',
        ),
      );
      expect(
        serviceKt,
        contains('@Volatile\n        var isAppForeground: Boolean = false'),
      );
      expect(serviceKt, contains('fun setAppForeground(foreground: Boolean)'));

      final anchor = serviceKt.indexOf('fun launchApp(context: Context)');
      expect(anchor, isNot(-1), reason: 'launchApp not found');
      final end = serviceKt.indexOf('\n        }', anchor);
      expect(end, isNot(-1), reason: 'launchApp closing brace not found');
      final body = serviceKt.substring(anchor, end);

      expect(body, contains('isAppForeground'));
      expect(body, contains('MainActivity::class.java'));
      expect(body, contains('action = ACTION_OPEN_APP'));
      expect(body, contains('Intent.FLAG_ACTIVITY_NEW_TASK'));
      expect(body, contains('Intent.FLAG_ACTIVITY_SINGLE_TOP'));
      expect(body, contains('startActivity('));
    });

    test('MainActivity exposes openApp mapped to the service launcher', () {
      if (!ready) return;

      expect(activityKt, contains('"openApp"'));
      expect(
        RegExp(
          r'"openApp"\s*->\s*\{[\s\S]*?FlamesBackgroundService\.launchApp\(',
        ).hasMatch(activityKt),
        isTrue,
      );
    });

    test('activity tracks app foreground state for the tap guard', () {
      if (!ready) return;

      final resumeAnchor = activityKt.indexOf('override fun onResume()');
      expect(resumeAnchor, isNot(-1), reason: 'onResume not found');
      final resumeEnd = activityKt.indexOf('\n    }', resumeAnchor);
      expect(resumeEnd, isNot(-1), reason: 'onResume closing brace not found');
      final resumeBody = activityKt.substring(resumeAnchor, resumeEnd);
      expect(resumeBody, contains('setAppForeground(true)'));

      final pauseAnchor = activityKt.indexOf('override fun onPause()');
      expect(pauseAnchor, isNot(-1), reason: 'onPause not found');
      final pauseEnd = activityKt.indexOf('\n    }', pauseAnchor);
      expect(pauseEnd, isNot(-1), reason: 'onPause closing brace not found');
      final pauseBody = activityKt.substring(pauseAnchor, pauseEnd);
      expect(pauseBody, contains('setAppForeground(false)'));
    });

    test('manifest keeps MainActivity singleTop for task reuse', () {
      if (!ready) return;

      expect(
        RegExp(
          r'android:name="\.MainActivity"[\s\S]*?android:launchMode="singleTop"',
        ).hasMatch(manifest),
        isTrue,
      );
    });
  });
}
