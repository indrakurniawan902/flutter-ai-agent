# Task T18.5-A: Camera capture lost-result recovery + structured failures

## Target Files (ONLY these)
- `lib/common/failure.dart` (extend)
- `lib/domain/tools/chat/camera_vision_service.dart` (extend contract)
- `lib/data/datasources/tools/chat/camera_vision_service.dart` (rewrite logic)
- `test/data/datasources/tools/chat/camera_vision_service_test.dart` (new)

## Files to NOT Touch
- `lib/common/injection/injection.config.dart` (generated)
- `lib/domain/tools/chat/tool_registry.dart`
- Any file not listed above.

## Background (verified facts, do not re-derive)
`camera_take_photo` fails on real devices: the Activity leaves the foreground while the camera
Intent is in flight and returns without a result. Current code maps `XFile? == null` to
`PermissionFailure('Image capture cancelled by user')` — misleading. `retrieveLostData()` is
never called. After a timed-out capture, a retry throws
`PlatformException(already_active, Image picker is already active)` and every later camera call
fails until process restart (no reset, no guard, no try/finally).

Bridge error frames carry ONLY `failure.message` (see
`lib/domain/services/gateway/gateway_rpc_receiver.dart:151-163`), so machine-readable failure
codes MUST be embedded in the message text.

## Goal

### 1. `lib/common/failure.dart` — add 4 failure classes (do not change existing ones)
Each with a STABLE machine-readable code token embedded in its default message:
- `CameraCancelledFailure` → message contains `camera_cancelled` — user dismissed the camera UI; caller should NOT auto-retry.
- `CameraLostResultFailure` → message contains `camera_lost_result` — Activity recreated/detached and no lost data could be recovered; caller SHOULD retry.
- `CameraBusyFailure` → message contains `camera_busy` — picker already active (already_active); caller SHOULD retry after settling.
- `CameraTimeoutFailure` → message contains `camera_timeout` — capture exceeded the app-side deadline; caller SHOULD retry.
Follow the existing const-constructor style (`const XFailure([super.message = '...'])`).

### 2. `lib/domain/tools/chat/camera_vision_service.dart` — extend contract
Add one method to `CameraVisionServiceBase` with doc comment:
```dart
/// Recovers a capture lost to an Activity recreation (image_picker lost-data API).
/// Right(null) when there is nothing to recover; Right(base64) on recovered capture;
/// Left(CameraLostResultFailure) when recovery itself failed. Never throws.
Future<Either<Failure, String?>> recoverLostCapture();
```

### 3. `lib/data/datasources/tools/chat/camera_vision_service.dart` — rewrite `takePhoto`
Keep the class shape (`@LazySingleton(as: CameraVisionServiceBase)`, `@factoryMethod create`,
existing `_maxDimension` 1024 / `_jpegQuality` 80, same base64 return type).

a) Add injectable deadline: constructor param `Duration captureTimeout = const Duration(seconds: 25)`
   stored as final field (25s < the bridge's 30s call timeout so the tool ALWAYS answers first).
b) Wrap every `pickImage` call (camera AND gallery) with `.timeout(captureTimeout, onTimeout: () => null)`
   — on timeout return `Left(CameraTimeoutFailure(...))` (distinguish timeout-null from real null).
c) `CameraSource.camera` path — BEFORE calling pickImage, call `retrieveLostData()`:
   - if the response has file(s) (e.g. `response.file != null` or `response.files` non-empty):
     treat as SUCCESSFUL capture — read bytes, base64-encode, return Right. This also clears the
     already_active latch left by a previous abandoned capture.
   - if `response.exception != null`: continue into a normal pickImage attempt anyway (do not
     short-circuit the user's current request with a stale error).
d) `null` result from pickImage (not timeout): call `retrieveLostData()` again:
   - response has file(s) → encode → Right (recovered success).
   - `response.exception != null` → `Left(CameraLostResultFailure(...))`.
   - response empty → `Left(CameraCancelledFailure(...))` (genuine user dismissal).
e) Catch `PlatformException` with code `already_active` → call `retrieveLostData()`:
   - file(s) recovered → Right (success).
   - otherwise → `Left(CameraBusyFailure(...))` (retryable, NOT terminal).
f) Catch `PlatformException` with a permission-denied code (e.g. `permissionDenied`) →
   `Left(PermissionFailure(...))` with the REAL platform message (this is a true permission bug).
g) Any other exception → `Left(ServerFailure('[camera_error] ...'))` (keep `[camera_error]` prefix
   in the message).
h) `recoverLostCapture()` implementation per the contract above: `retrieveLostData()` →
   file(s) → Right(base64); empty → `Right(null)`; exception → `Left(CameraLostResultFailure)`.
   Wrap in try/catch so it NEVER throws (return `Right(null)` on unexpected internal errors).
i) Guard lost-data recovery to the camera path only (gallery picks have no lost-data semantics on
   Android; if `retrieveLostData` is harmless for gallery you may still guard it to camera).

### 4. Unit tests — `test/data/datasources/tools/chat/camera_vision_service_test.dart`
Use `TestWidgetsFlutterBinding.ensureInitialized()` and mock the picker via
`ImagePickerPlatform.instance = <your mock>` (subclass/implement `ImagePickerPlatform` from
`package:image_picker_platform_interface/image_picker_platform.dart`, exported by image_picker).
Override `pickImage(...)` and `retrieveLostData()` returning `LostDataResponse(...)`.
Inject a short `captureTimeout` for the timeout branch. Required cases:
1. pickImage returns XFile → Right with base64 of the bytes.
2. pickImage returns null, retrieveLostData returns empty LostDataResponse → Left CameraCancelledFailure.
3. pickImage returns null, retrieveLostData returns LostDataResponse with exception (type retrieve) → Left CameraLostResultFailure.
4. pickImage returns null, retrieveLostData returns a file → Right with that file's base64 (recovered = SUCCESS).
5. pickImage throws PlatformException('already_active'), retrieveLostData returns a file → Right (latch cleared + recovered).
6. pickImage throws PlatformException('already_active'), retrieveLostData empty → Left CameraBusyFailure.
7. pickImage throws PlatformException('permissionDenied') → Left PermissionFailure.
8. pickImage hangs forever (Completer) with short captureTimeout → Left CameraTimeoutFailure within test timeout.
9. `recoverLostCapture()` with a recovered file → Right(base64); with empty → Right(null).
10. camera-path entry calls retrieveLostData first: platform mock records that retrieveLostData was
    called BEFORE pickImage on a camera source call (order assertion via a call-log list).

## Context & Architectural Rules
- Clean Architecture: domain = flutter-free contracts, data = implementations. The data impl
  imports `package:flutter_ai_agent/common/failure.dart` (existing pattern, lines 1-9 of current file).
- `LostDataResponse` API (image_picker_android 0.8.13+23 / platform interface 2.11.1, resolved
  version image_picker 1.2.3): fields `file` (XFile?), `files` (List<XFile>), `exception`
  (PlatformException?), `type`, plus `isEmpty`. `LostDataResponse.empty()` exists.
- Do NOT read ~/.pub-cache — everything you need is stated here.
- Never prefix flutter commands with flock (the wrapper already locks; nested flock deadlocks).

## Definition of Done (DoD)
- Run: flutter analyze  (0 issues)
- Run: flutter test test/data/datasources/tools/chat/camera_vision_service_test.dart  (100% pass)
- Report the REAL tail output of both commands in your final message.
- You MUST actually apply the edits (previous workers sometimes exited 0 having only read files).

## [ADDED CONTEXT] — existing test file (UPDATE, not create)
test/data/datasources/tools/chat/camera_vision_service_test.dart ALREADY EXISTS (244 lines).
It mocks ImagePicker directly (class MockImagePicker extends Mock implements ImagePicker) and
the service accepts an injectable `picker` in its constructor. KEEP that mocking approach —
mock ImagePicker directly, mock its `retrieveLostData()` method too (it returns
`Future<LostDataResponse>`; construct real `LostDataResponse(...)` values, not mocks).
Change the target test file in this spec to: EXTEND this existing file with the new cases
(2-10) and REVISE outdated assertions:
- 'returns PermissionFailure when user cancels (null XFile)' must become:
  pickImage null + retrieveLostData empty -> CameraCancelledFailure (message contains
  'camera_cancelled').
- 'returns ServerFailure when pickImage throws' with a generic exception may stay ServerFailure
  but the message should now contain '[camera_error]'.
- Success cases stay valid; they additionally need retrieveLostData stubbed (default: empty
  LostDataResponse) since the camera path now calls it before pickImage.
- Constructor gains a captureTimeout param; keep it optional/default-25s so existing
  constructions compile.
