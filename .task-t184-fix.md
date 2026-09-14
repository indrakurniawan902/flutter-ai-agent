# T18.4 FIX ROUND: reviewer findings on platform TTS fallback

Apply ONLY these targeted fixes to the already-implemented platform TTS fallback.
Do NOT refactor anything else. Do NOT re-run build_runner.

## Fix 1 — Mute parity for the platform engine (real bug)
`_speakWithPlatform` calls `_platformTts.setVolume(0.0)` when `_muted`, but nothing
ever restores 1.0 — flutter_tts volume persists, so after one muted platform speak
all later unmuted platform speech is silent.
Fix:
- In `VoiceOutputService.setMuted`: add
  `unawaited(_platformTts.setVolume(muted ? 0.0 : 1.0));` next to the existing
  `_player.setVolume` call.
- Remove the `if (_muted) await _platformTts.setVolume(0.0);` line from
  `_speakWithPlatform` (volume is now owned by setMuted, same as the byte player).

## Fix 2 — stop()/interrupt() must cover platform speech (real bug)
With `awaitSpeakCompletion(true)`, `_speakWithPlatform` awaits the whole utterance;
`interrupt()` during platform speech neither stops it nor prevents the status being
clobbered back to idle.
Fix:
- Add field `int _platformEpoch = 0;`
- In `stop()`: call `await _platformTts.stop();` before/alongside `_player.stop()`,
  and increment `_platformEpoch++`.
- In `interrupt()`: call `_platformEpoch++` too (its `stop()` call runs the same code).
- In `_speakWithPlatform`: capture `final epoch = _platformEpoch;` BEFORE awaiting
  `_platformTts.speak(...)`; after the await returns:
  - if `_platformEpoch != epoch` → speech was interrupted: return `const Right(unit)`
    WITHOUT touching `_playing`, status, or `lastEngineUsed` (stop() already emitted
    the stopped status).
  - else set `_lastEngineUsed = TtsEngine.androidTts`, `_playing = false`, status
    idle, return Right — unchanged current behavior.

## Fix 3 — wire the DI-registered PlatformTtsEngine (dead wiring)
`VoiceOutputService.create(TtsClient)` never receives the registered
`PlatformTtsEngine`, so production uses the constructor fallback instance.
Fix:
- Change the factory to
  `factory VoiceOutputService.create(TtsClient ttsClient, PlatformTtsEngine platformTts) => VoiceOutputService(ttsClient: ttsClient, platformTts: platformTts);`
- HAND-EDIT `lib/common/injection/injection.config.dart` ONLY: change the
  VoiceOutputServiceBase factory line to pass the second arg:
  `() => _i753.VoiceOutputService.create(gh<_i753.TtsClient>(), gh<_i753.PlatformTtsEngine>()),`
  DO NOT run build_runner (it re-introduces config drift). If you cannot find the
  exact line, leave config unchanged and report it.
- NOTE: this is intentionally NOT "unregistered dependency" — check how other
  create() factories in the file pass gh<> args and match the pattern.
  If `flutter analyze` flags it, report the exact error in your summary instead of
  improvising (the lead will reconcile config).

## Fix 4 — tests (mocktail, add to voice_output_service_test.dart)
In the 'TTS engine selection & platform fallback' group add:
1. `setMuted parity reaches platform engine`: stub platform setVolume; call
   `service.setMuted(true)` then `service.setMuted(false)`; verify
   `mockPlatformTts.setVolume(0.0)` then `(1.0)` each called (times(1)).
2. `stop during platform speech keeps stopped status`: use a Completer<bool> for
   `mockPlatformTts.speak` (`thenAnswer((_) => completer.future)`); start
   `speakText` (don't await yet), await a microtask, call `service.stop()`, then
   `completer.complete(true)` and await the speakText future. Expect: result
   Right, `mockPlatformTts.stop()` called (times(1)), status stays
   `VoiceOutputStatus.stopped` (NOT idle), and `lastEngineUsed == TtsEngine.androidTts`
   (partial speech did come from the engine — if you set lastEngineUsed only on
   non-interrupted completion, instead expect it to stay null; pick ONE behavior
   and make the test match; do not leave it ambiguous).
3. Keep all existing tests passing.

## Fix 5 — comment (non-blocking)
Above the platform branch in `queueText`, add one line:
`// Platform speech is immediate (no byte queue); streaming flush awaits completion.`

## Do NOT change
- `isRemoteConfigured()` behavior (reviewer's item 3 is BY DESIGN per the card:
  the default chat gateway has no speech endpoint, so we skip the doomed remote
  attempt; synthesize()'s defaultBaseUrl fallback remains for other callers).
- Anything in camera_vision / local_memory files (other tasks own them).

## DoD
- `flutter analyze` — zero NEW issues in voice_output/tool_registry/injection files
  (pre-existing issues in camera_vision/local_memory tests belong to other tasks).
- `flutter test test/data/datasources/tools/chat/voice_output_service_test.dart
  test/domain/tools/chat/tool_registry_test.dart` — 100% pass.
- Report real command output tails.
