# Task T18.5 Sub-task 1: Camera capture lost-result recovery, structured failures, and unit tests

## Target Files (ONLY these 4 files)
- `lib/common/failure.dart`
- `lib/domain/tools/chat/camera_vision_service.dart`
- `lib/data/datasources/tools/chat/camera_vision_service.dart`
- `test/data/datasources/tools/chat/camera_vision_service_test.dart`

## Files to NOT Touch
- `lib/common/injection/injection.config.dart` (generated)
- `lib/domain/tools/chat/tool_registry.dart`
- `android/`
- Any file not listed under Target Files.

## Background & Specifications
`camera_take_photo` fails on real devices because the Activity leaves foreground during camera Intent and returns without result. Currently `XFile? == null` maps to `PermissionFailure('Image capture cancelled by user')` — misleading. `retrieveLostData()` is never called. After a timed-out capture, a retry throws `PlatformException(already_active, Image picker is already active)` and wedges the tool.

### 1. `lib/common/failure.dart`
Add these 4 failure classes (extend `Failure`, const constructors):
```dart
class CameraCancelledFailure extends Failure {
  const CameraCancelledFailure([
    super.message = 'camera_cancelled: User cancelled image capture',
  ]);
}

class CameraLostResultFailure extends Failure {
  const CameraLostResultFailure([
    super.message = 'camera_lost_result: Camera result lost to Activity recreation',
  ]);
}

class CameraBusyFailure extends Failure {
  const CameraBusyFailure([
    super.message = 'camera_busy: Image picker is already active',
  ]);
}

class CameraTimeoutFailure extends Failure {
  const CameraTimeoutFailure([
    super.message = 'camera_timeout: Image capture timed out',
  ]);
}
```

### 2. `lib/domain/tools/chat/camera_vision_service.dart`
Add `recoverLostCapture` to `CameraVisionServiceBase`:
```dart
/// Recovers a capture lost to an Activity recreation (image_picker lost-data API).
/// Right(null) when there is nothing to recover; Right(base64) on recovered capture;
/// Left(CameraLostResultFailure) when recovery itself failed. Never throws.
Future<Either<Failure, String?>> recoverLostCapture();
```

### 3. `lib/data/datasources/tools/chat/camera_vision_service.dart`
Keep class shape: `@LazySingleton(as: CameraVisionServiceBase)`, `@factoryMethod factory CameraVisionService.create() => CameraVisionService();`.
- Add constructor parameter: `Duration captureTimeout = const Duration(seconds: 25)` stored as final field `captureTimeout`.
- In `takePhoto`:
  - Map `source`: `final imageSource = (source == CameraSource.gallery) ? ImageSource.gallery : ImageSource.camera;`
  - When `imageSource == ImageSource.camera`:
    - Before calling `pickImage`, call `await _picker.retrieveLostData()`.
    - If `lostData.file != null` or `lostData.files.isNotEmpty`:
      read bytes, encode base64, return `Right(base64)` immediately. (If retrieveLostData throws, ignore and continue to pickImage).
  - Wrap `_picker.pickImage(...)` call in `.timeout(captureTimeout, onTimeout: () => null)` (track if timedOut).
  - Catch `PlatformException`:
    - If `e.code == 'already_active'`:
      - Call `await _picker.retrieveLostData()`.
      - If recovered file exists -> return `Right(base64)`.
      - Otherwise -> return `const Left(CameraBusyFailure())`.
    - If `e.code.toLowerCase().contains('permission')` or `(e.message ?? '').toLowerCase().contains('permission')`:
      - Return `Left(PermissionFailure(e.message ?? 'Camera permission denied'))`.
    - Otherwise:
      - Return `Left(ServerFailure('[camera_error] ${e.message ?? e.code}'))`.
  - If `timedOut`: return `const Left(CameraTimeoutFailure())`.
  - If `file == null`:
    - Call `await _picker.retrieveLostData()`.
    - If recovered file exists -> return `Right(base64)`.
    - If `lostData.exception != null` -> return `Left(CameraLostResultFailure(lostData.exception!.message ?? 'camera_lost_result'))`.
    - Otherwise -> return `const Left(CameraCancelledFailure())`.
  - Catch general exceptions on readAsBytes / etc. -> return `Left(ServerFailure('[camera_error] $e'))`.
- Implement `recoverLostCapture()`:
  - Call `await _picker.retrieveLostData()`.
  - If file exists -> return `Right(base64)`.
  - If `lostData.exception != null` -> return `Left(CameraLostResultFailure(lostData.exception!.message ?? 'camera_lost_result'))`.
  - Return `const Right(null)`.
  - Wrap entire body in `try/catch` so it never throws, returning `const Right(null)` on unexpected exception.

### 4. `test/data/datasources/tools/chat/camera_vision_service_test.dart`
Use Mocktail to mock the facade `ImagePicker`:
```dart
class MockImagePicker extends Mock implements ImagePicker {}
class MockXFile extends Mock implements XFile {}
```
In `setUp`:
```dart
mockPicker = MockImagePicker();
service = CameraVisionService(
  picker: mockPicker,
  captureTimeout: const Duration(milliseconds: 100),
);
```
Stub `mockPicker.retrieveLostData()` by default to return `LostDataResponse.empty()`.
Write/update comprehensive tests covering:
1. Camera capture success: pickImage returns XFile -> Right(base64). Verify `retrieveLostData()` was called BEFORE `pickImage` on camera source.
2. Gallery pick success: pickImage returns XFile -> Right(base64). Verify `retrieveLostData()` was NOT called on gallery source.
3. Pre-existing lost data on camera entry: `retrieveLostData()` returns file -> Right(base64) returned immediately without calling `pickImage`.
4. pickImage returns null, retrieveLostData is empty -> Left(CameraCancelledFailure) with 'camera_cancelled'.
5. pickImage returns null, retrieveLostData has file -> Right(base64) (recovered success).
6. pickImage returns null, retrieveLostData has exception -> Left(CameraLostResultFailure) with 'camera_lost_result'.
7. pickImage throws PlatformException('already_active'), retrieveLostData has file -> Right(base64).
8. pickImage throws PlatformException('already_active'), retrieveLostData empty -> Left(CameraBusyFailure) with 'camera_busy'.
9. pickImage throws PlatformException('permissionDenied') -> Left(PermissionFailure).
10. pickImage hangs forever (Completer), captureTimeout expires -> Left(CameraTimeoutFailure) with 'camera_timeout'.
11. pickImage throws generic Exception -> Left(ServerFailure) with '[camera_error]'.
12. `recoverLostCapture()` returns Right(base64) when file present, Right(null) when empty, Left(CameraLostResultFailure) on exception.
13. `recoverLostCapture()` returns Right(null) and never throws if retrieveLostData throws an unexpected Exception.

## Definition of Done (DoD)
- Run: flutter analyze (0 issues)
- Run: flutter test test/data/datasources/tools/chat/camera_vision_service_test.dart (100% pass)
- Report the REAL output of both commands in your final message.
- Do NOT read ~/.pub-cache.
