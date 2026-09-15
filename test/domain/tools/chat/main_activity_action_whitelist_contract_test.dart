import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MainActivity action whitelist (read-only)', () {
    late bool ready;
    late String activityKt;
    late String manifest;

    setUpAll(() {
      final root = Directory.current.path;
      final activityFile = File(
        '$root/android/app/src/main/kotlin/ai/hermes/flames/MainActivity.kt',
      );
      final manifestFile = File(
        '$root/android/app/src/main/AndroidManifest.xml',
      );

      ready = activityFile.existsSync() && manifestFile.existsSync();
      if (!ready) {
        markTestSkipped('MainActivity native files not found');
        return;
      }

      activityKt = activityFile.readAsStringSync();
      manifest = manifestFile.readAsStringSync();
    });

    String bracedBlock(String source, String anchor) {
      final start = source.indexOf(anchor);
      if (start < 0) fail('missing anchor: $anchor');
      final open = source.indexOf('{', start);
      var depth = 0;
      for (var i = open; i < source.length; i++) {
        if (source[i] == '{') depth++;
        if (source[i] == '}') {
          depth--;
          if (depth == 0) return source.substring(open, i + 1);
        }
      }
      fail('unbalanced braces after: $anchor');
    }

    String extractBody() =>
        bracedBlock(activityKt, 'private fun extractActionFromIntent');

    test('extractActionFromIntent matches the extra exactly without normalizing it', () {
      if (!ready) return;

      final body = extractBody();
      expect(body, contains('extra_flames_action'));
      expect(body, contains('in ALLOWED_ACTIONS'));
      for (final forbidden in const [
        '.lowercase(',
        '.trim(',
        '.isNullOrBlank(',
        '.uppercase(',
      ]) {
        expect(
          body,
          isNot(contains(forbidden)),
          reason: 'the Kotlin layer must not normalize $forbidden',
        );
      }
    });

    test('the whitelist holds exactly the three lowercase action literals', () {
      if (!ready) return;

      final companion = bracedBlock(activityKt, 'private companion object');
      expect(companion, contains('"voice_input"'));
      expect(companion, contains('"cancel_voice"'));
      expect(companion, contains('"quick_status"'));

      final literals = RegExp(r'"[^"]*"').allMatches(companion).length;
      expect(
        literals,
        3,
        reason: 'only the three whitelisted actions may be declared, '
            'found $literals quoted literals',
      );
    });

    test('share and view intents return null before the extra is read', () {
      if (!ready) return;

      final body = extractBody();
      expect(body, contains('Intent.ACTION_SEND'));
      expect(body, contains('Intent.ACTION_SEND_MULTIPLE'));
      expect(body, contains('Intent.ACTION_VIEW'));
      expect(body, contains('return null'));

      final guardIndex = body.indexOf('Intent.ACTION_SEND');
      final extraIndex = body.indexOf('extra_flames_action');
      expect(
        guardIndex,
        lessThan(extraIndex),
        reason: 'the share guard must run before the extra is read so a '
            'piggybacked action on a share intent is dropped',
      );
    });

    test('the dead quick-tile fallback is gone from MainActivity', () {
      if (!ready) return;

      // Never sent by anyone: FlamesQuickTile.onClick() posts
      // FlamesBackgroundService.ACTION_VOICE_INPUT to the service directly.
      // Since voice_input is whitelisted, keeping the fallback would have kept
      // a spoofable path alive via that forgeable action string.
      expect(activityKt, isNot(contains('ACTION_QUICK_TILE_TRIGGER')));
      expect(activityKt, isNot(contains('fallbackAction')));
    });

    test('RationaleActivity carries the same permission as its alias', () {
      if (!ready) return;

      final start = manifest.indexOf('android:name=".RationaleActivity"');
      expect(start, greaterThanOrEqualTo(0));
      final open = manifest.lastIndexOf('<activity', start);
      final close = manifest.indexOf('</activity>', start);
      final activity = manifest.substring(open, close);

      expect(
        activity,
        contains(
          'android:permission="android.permission.START_VIEW_PERMISSION_USAGE"',
        ),
      );

      final aliasStart = manifest.indexOf(
        'android:targetActivity=".RationaleActivity"',
      );
      expect(aliasStart, greaterThanOrEqualTo(0));
      final aliasOpen = manifest.lastIndexOf('<activity-alias', aliasStart);
      final aliasClose = manifest.indexOf('</activity-alias>', aliasStart);
      final alias = manifest.substring(aliasOpen, aliasClose);
      expect(
        alias,
        contains(
          'android:permission="android.permission.START_VIEW_PERMISSION_USAGE"',
        ),
      );
    });
  });
}
