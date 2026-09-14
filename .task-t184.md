# T18.4: speak_text fails on device — add local Android TTS fallback (flutter_tts)

## Background
`speak_text` tool fails on real devices when the configured gateway/router has no
`/v1/audio/speech` endpoint: `DioTtsClient.synthesize` maps 404 to
`UnsupportedEndpointException` and `VoiceOutputService.speakText` returns a Left failure.
We must make platform TTS (flutter_tts) the fallback so speech always works offline.

## Design decisions (FIXED — do not redesign)
1. New domain enum + contract in `lib/domain/tools/chat/voice_output_service.dart`:
   - `enum TtsEngine { remoteTts, androidTts }`
   - `abstract class PlatformTtsEngine` (domain must stay flutter/dio-free):
     ```dart
     abstract class PlatformTtsEngine {
       bool get isAvailable;
       Future<bool> speak(String text, {String? voice, double? speed});
       Future<void> setVolume(double volume);
       Future<void> stop();
     }
     ```
   - Add `TtsEngine? get lastEngineUsed;` to `VoiceOutputServiceBase` (null initially).

2. New data class in `lib/data/datasources/tools/chat/voice_output_service.dart`:
   - `@LazySingleton(as: PlatformTtsEngine) class FlutterTtsPlatformEngine implements PlatformTtsEngine`
   - Wraps `FlutterTts` from `package:flutter_tts/flutter_tts.dart` (version 4.2.5).
   - Use the SAME safe-wrapper pattern as `DefaultAudioPlayerWrapper`: private
     nullable holder created in try/catch; EVERY method body wrapped in try/catch,
     returning safe defaults (`isAvailable => false`, `speak => false`) when the
     engine is null or throws.
   - On first successful construction configure once:
     `await engine.awaitSpeakCompletion(true);` (so `speak(...)`'s Future completes
     when speech finishes), then `setLanguage` may be skipped — device default
     locale is acceptable. `speak(text)` returns the platform result; map truthy
     results (1 / dynamic success) to true.
   - API surface (verified, from .ref/flutter_tts/lib/flutter_tts.dart):
     - `Future<dynamic> speak(String text, {bool focus = false})`
     - `Future<dynamic> awaitSpeakCompletion(bool awaitCompletion)`
     - `Future<dynamic> setSpeechRate(double rate)`, `setVolume(double)`, `setPitch(double)`
     - `Future<dynamic> stop()`
     - `void setStartHandler(VoidCallback)`, `setCompletionHandler(VoidCallback)`,
       `setErrorHandler(ErrorHandler)` (we do NOT need handlers because of awaitSpeakCompletion)

3. `TtsClient` abstract (same data file) gains:
   - `Future<bool> isRemoteConfigured();`
   - `DioTtsClient.isRemoteConfigured()`: return true if the injected `_baseUrl` is
     non-empty after trim; otherwise read `_secureStorageService?.getBaseUrl()` and
     return true only if stored value is non-empty. IMPORTANT: do NOT fall back to
     `AppConstants.defaultBaseUrl` for this check (the default chat gateway has no
     speech endpoint — attempting it always 404s and wastes a round-trip).

4. `VoiceOutputService` engine selection (FIXED algorithm):
   - Constructor gains optional `PlatformTtsEngine? platformTts` (defaults to a
     safe-created `FlutterTtsPlatformEngine` when null); keep existing
     `VoiceOutputService.create(ttsClient)` factory working by passing nothing for
     platformTts.
   - In `speakText` and `queueText`:
     1. If `await _tts.isRemoteConfigured()` is false → use platform directly
        (do NOT call remote synthesize at all).
     2. Else try remote `synthesize`; on `UnsupportedEndpointException` (and ONLY
        that exception; other errors keep current failure behavior) → fall back to
        platform.
     3. Platform path: set status loading → if `_muted` call
        `platformTts.setVolume(0.0)` (and restore 1.0 when unmuted later is NOT
        needed — setMuted already owns volume parity) → `speak(...)`; set
        `_playing` semantics: mark status `playing` while speaking, then `idle`
        after completion; if `speak` returns false or throws → failure via `_fail`
        and return Left(ServerFailure(...)).
     4. Set `lastEngineUsed = TtsEngine.remoteTts` on successful remote path,
        `TtsEngine.androidTts` on successful platform path. Remote success flows
        through the existing `queueAudio` byte-player path unchanged.
   - Failure only when BOTH paths fail. Empty-text validation stays first.

5. Tool result must state the engine (`lib/domain/tools/chat/tool_registry.dart`,
   `registerVoiceOutputTools`): on success, the JSON becomes:
   ```dart
   jsonEncode({
     'status': 'spoken',
     'text': text,
     'engine': service.lastEngineUsed == TtsEngine.androidTts ? 'android_tts' : 'remote_tts',
   })
   ```

6. `pubspec.yaml`: add dependency `flutter_tts: ^4.2.5` (already known-good version;
   run `flutter pub get` after editing).

## Dependency injection
- Registrations are annotation-driven; after code changes run
  `dart run build_runner build --delete-conflicting-outputs` to regenerate
  `lib/common/injection/injection.config.dart`.
- CRITICAL: after regen, `git diff lib/common/injection/injection.config.dart` and
  verify the diff ONLY contains the new `FlutterTtsPlatformEngine` registration and
  the updated `VoiceOutputService` factory (it may gain a platformTts argument).
  Revert any unrelated drift with `git checkout --` + targeted re-edit (the checked-in
  config is sometimes hand-edited; build_runner regen can re-introduce unregistered
  scalar lookups like `gh<double>()` that only blow up at test runtime).

## Tests (required, mocktail, AAA pattern)
- `test/helpers/mocks.dart`: add `class MockPlatformTtsEngine extends Mock implements PlatformTtsEngine {}`.
- `test/data/datasources/tools/chat/voice_output_service_test.dart`:
  - Existing tests: `MockTtsClient` must now stub `isRemoteConfigured()` (stub as
    `true` in setUp, plus existing `synthesize` stubs) — mocktail throws on
    unstubbed calls, keep ALL existing tests passing unchanged in intent.
  - Construct service with `platformTts: mockPlatformTts` in setUp; stub
    `isAvailable`, `speak`, `setVolume`, `stop` with safe answers.
  - NEW group `TTS engine selection & platform fallback`:
    1. `remote 404 falls back to platform TTS`: mockTtsClient.synthesize throws
       `UnsupportedEndpointException` (const, already in data file);
       expect `speakText` returns Right, `mockPlatformTts.speak` called exactly once,
       `service.lastEngineUsed == TtsEngine.androidTts`, status returns to idle.
    2. `no remote base URL uses platform directly`: stub
       `isRemoteConfigured() => false`; expect platform speak called once and
       `verifyNever(() => mockTtsClient.synthesize(...))`;
       `lastEngineUsed == TtsEngine.androidTts`.
    3. `remote success keeps byte-player path`: synthesize returns bytes;
       expect player.play called with BytesSource, platform speak NOT called,
       `lastEngineUsed == TtsEngine.remoteTts`.
    4. `both paths fail -> Left`: remote throws UnsupportedEndpointException AND
       platform `speak` returns false; expect Left(ServerFailure).
- `test/domain/tools/chat/tool_registry_test.dart`: update the speak_text
  delegation test to decode the Right value JSON and assert `engine` key exists
  (stub `lastEngineUsed` on the mock to `TtsEngine.androidTts`); keep existing
  failure/validation tests intact.

## Files you MAY touch
- pubspec.yaml (+ pubspec.lock via pub get)
- lib/domain/tools/chat/voice_output_service.dart
- lib/data/datasources/tools/chat/voice_output_service.dart
- lib/domain/tools/chat/tool_registry.dart (registerVoiceOutputTools ONLY)
- lib/common/injection/injection.config.dart (build_runner regen + drift revert)
- test/helpers/mocks.dart
- test/data/datasources/tools/chat/voice_output_service_test.dart
- test/domain/tools/chat/tool_registry_test.dart

## Files you must NOT touch
- Anything else in lib/ or test/, android/, analysis_options.yaml, docs/.

## Hard rules
- DO NOT read anything under ~/.pub-cache (sandbox blocks it). The flutter_tts
  source is copied at `.ref/flutter_tts/` — read `.ref/flutter_tts/lib/flutter_tts.dart`
  if you need API details.
- NEVER prefix flutter/dart commands with `flock` (the `~/.local/bin/flutter`
  wrapper already self-locks; nested flock deadlocks).
- Do NOT add unrequested dependencies or packages.
- Do NOT use Bloc; Cubit-only repo (irrelevant here but do not introduce events).
- Apply real edits — a run that only reads files and exits is a failure.

## Definition of Done
- `flutter pub get` succeeds.
- `flutter analyze` → "No issues found!".
- `flutter test test/data/datasources/tools/chat/voice_output_service_test.dart
  test/domain/tools/chat/tool_registry_test.dart` → 100% pass.
- `flutter test` (full suite) → 100% pass.
- Report the REAL tail output of analyze and the full-suite test summary
  (lines like "All tests passed!").
