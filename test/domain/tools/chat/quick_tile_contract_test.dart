import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('quick tile native wiring (read-only)', () {
    late bool ready;
    late String quickTileKt;
    late String backgroundServiceKt;
    late String manifest;
    late String activityKt;

    setUpAll(() {
      final root = Directory.current.path;
      final quickTileFile = File(
        '$root/android/app/src/main/kotlin/ai/hermes/flames/FlamesQuickTile.kt',
      );
      final backgroundFile = File(
        '$root/android/app/src/main/kotlin/ai/hermes/flames/FlamesBackgroundService.kt',
      );
      final manifestFile = File(
        '$root/android/app/src/main/AndroidManifest.xml',
      );
      final activityFile = File(
        '$root/android/app/src/main/kotlin/ai/hermes/flames/MainActivity.kt',
      );

      ready = quickTileFile.existsSync() &&
          backgroundFile.existsSync() &&
          manifestFile.existsSync() &&
          activityFile.existsSync();
      if (!ready) {
        markTestSkipped('quick tile native files not found');
        return;
      }

      quickTileKt = quickTileFile.readAsStringSync();
      backgroundServiceKt = backgroundFile.readAsStringSync();
      manifest = manifestFile.readAsStringSync();
      activityKt = activityFile.readAsStringSync();
    });

    int countOf(String source, String needle) =>
        RegExp(RegExp.escape(needle)).allMatches(source).length;

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

    String onClickBody() => bracedBlock(quickTileKt, 'override fun onClick()');

    String serviceBlock(String anchor) {
      final index = manifest.indexOf(anchor);
      final open = manifest.lastIndexOf('<service', index);
      final close = manifest.indexOf('</service>', index);
      return manifest.substring(open, close);
    }

    test('tile tap never launches an activity', () {
      if (!ready) return;

      final body = onClickBody();
      for (final forbidden in const [
        'startActivity',
        'startActivityAndCollapse',
        'PendingIntent',
        'MainActivity',
      ]) {
        expect(
          body,
          isNot(contains(forbidden)),
          reason: 'onClick must not contain $forbidden',
        );
      }

      expect(countOf(quickTileKt, 'startActivity'), 0);
      expect(countOf(quickTileKt, 'startActivityAndCollapse'), 0);
      expect(countOf(quickTileKt, 'PendingIntent'), 0);
      expect(countOf(quickTileKt, 'startForegroundService('), 2);
    });

    test('companion still declares ACTION_QUICK_TILE_TRIGGER', () {
      if (!ready) return;

      final companion = bracedBlock(quickTileKt, 'companion object {');
      expect(companion, contains('const val ACTION_QUICK_TILE_TRIGGER'));
    });

    test('tile tap starts exactly one headless voice turn', () {
      if (!ready) return;

      final body = onClickBody();
      expect(body, contains('FlamesBackgroundService::class.java'));
      expect(body, contains('FlamesBackgroundService.ACTION_VOICE_INPUT'));
      for (final forbidden in const [
        'VoiceTurnService',
        'runTurn',
        'MediaRecorder',
        'AudioRecord',
      ]) {
        expect(
          body,
          isNot(contains(forbidden)),
          reason: 'onClick must not contain $forbidden',
        );
      }
      expect(body, contains('startForegroundService('));
      expect(body, contains('startService('));
      expect(body, contains('Build.VERSION.SDK_INT'));
    });

    test('tile click does not flip the tile state', () {
      if (!ready) return;

      final body = onClickBody();
      expect(body, isNot(contains('tile.state')));
      expect(body, isNot(contains('updateTile()')));
      expect(body, isNot(contains('Tile.STATE_ACTIVE')));
    });

    test('updateTileState drives the tile from the recording status', () {
      if (!ready) return;

      expect(quickTileKt, contains('fun updateTileState(active: Boolean)'));
      final body = bracedBlock(
        quickTileKt,
        'fun updateTileState(active: Boolean)',
      );
      expect(body, contains('Tile.STATE_ACTIVE'));
      expect(body, contains('Tile.STATE_INACTIVE'));
      expect(body, contains('active'));
    });

    test('syncTileAppearance does not read service liveness', () {
      if (!ready) return;

      final sync = bracedBlock(quickTileKt, 'private fun syncTileAppearance()');
      expect(sync, isNot(contains('isServiceRunning')));

      final removed = bracedBlock(quickTileKt, 'override fun onTileRemoved()');
      expect(removed, contains('isServiceRunning'));
    });

    test('onTileRemoved cancels the voice turn behind a try/catch', () {
      if (!ready) return;

      final body = bracedBlock(quickTileKt, 'override fun onTileRemoved()');
      expect(body, contains('FlamesBackgroundService.ACTION_CANCEL_VOICE'));
      expect(body, contains('try {'));
      expect(body, contains('catch'));
    });

    test('onStopListening never starts or cancels a voice turn', () {
      if (!ready) return;

      final body = bracedBlock(quickTileKt, 'override fun onStopListening()');
      expect(body, isNotEmpty);
      expect(body, contains('super.onStopListening()'));
      for (final forbidden in const [
        'ACTION_VOICE_INPUT',
        'ACTION_CANCEL_VOICE',
        'startService',
        'startForegroundService',
        'VoiceTurnService',
      ]) {
        expect(
          body,
          isNot(contains(forbidden)),
          reason: 'onStopListening must not contain $forbidden',
        );
      }
    });

    test('service declares ACTION_CANCEL_VOICE and forwards it to Dart', () {
      if (!ready) return;

      expect(
        backgroundServiceKt,
        contains(
          'const val ACTION_CANCEL_VOICE = '
          '"ai.hermes.flames.action.CANCEL_VOICE"',
        ),
      );
      final branch = bracedBlock(backgroundServiceKt, 'ACTION_CANCEL_VOICE ->');
      expect(branch, contains('onActionReceived'));
      expect(branch, contains('"cancel_voice"'));
    });

    test('voice and cancel branches promote to foreground', () {
      if (!ready) return;

      for (final anchor in const [
        'ACTION_VOICE_INPUT ->',
        'ACTION_CANCEL_VOICE ->',
      ]) {
        final branch = bracedBlock(backgroundServiceKt, anchor);
        expect(branch, contains('startForeground('), reason: anchor);
      }
    });

    test('manifest binds the quick settings tile', () {
      if (!ready) return;

      final block = serviceBlock('.FlamesQuickTile');
      expect(block, contains('android:name=".FlamesQuickTile"'));
      expect(
        block,
        contains(
          'android:permission="android.permission.BIND_QUICK_SETTINGS_TILE"',
        ),
      );
      expect(block, contains('android:exported="true"'));
      expect(
        RegExp(
          r'<action\s+android:name="android\.service\.quicksettings\.action\.QS_TILE"\s*/>',
        ).hasMatch(block),
        isTrue,
      );
    });

    test('manifest keeps the background service foreground contract', () {
      if (!ready) return;

      final block = serviceBlock('.FlamesBackgroundService');
      expect(
        block,
        contains(
          'android:foregroundServiceType="specialUse|dataSync|microphone"',
        ),
      );
      expect(block, contains('android:exported="false"'));
    });

    test('MainActivity keeps the tile trigger plumbing', () {
      if (!ready) return;

      expect(
        activityKt,
        contains('FlamesQuickTile.ACTION_QUICK_TILE_TRIGGER'),
      );
      expect(activityKt, contains('"getPendingAction"'));
      expect(activityKt, contains('"clearPendingAction"'));
    });
  });
}
