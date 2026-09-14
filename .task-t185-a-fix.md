# Task T18.5-A-fix: repair mock layer in camera_vision_service_test.dart

## Context
A previous worker implemented T18.5-A correctly (failure classes, domain contract, data-layer
rewrite all compile clean: `flutter analyze lib/... camera_vision_service.dart
lib/domain/tools/chat/camera_vision_service.dart lib/common/failure.dart` -> 0 issues) but died
mid-task on a sandbox permission while fixing the TEST file. The test file's LOGIC is good —
only its MOCKING LAYER is wrong. It mocks `ImagePickerPlatform.instance` with wrong signatures.

## Current analyze errors on the test file (verified, 15 issues)
- error: `LostDataResponse` not returnable from `Future<LostData>` at lines 38, 40
  (platform interface's `retrieveLostData()` returns `Future<LostData>`, not LostDataResponse)
- error: wrong named params at lines 51-57 (`imageSource`/`maxWidth`/`maxHeight`/`imageQuality`/
  `preferredCameraDevice`/`requestFullMetadata` are NOT params of
  `ImagePickerPlatform.getImageFromSource`; its real signature is
  `getImageFromSource({required ImageSource source, ImagePickerOptions options})`)
- info: unnecessary `dart:typed_data` import (line 3)
- info: unnecessary `package:image_picker/image_picker.dart` import (line 10)
- info: `image_picker_platform_interface` is not a direct dependency
  (depend_on_referenced_packages, line 11)
- info: deprecated `retrieveLostData` on the platform interface (lines 35, 99, 284)

## Verified API facts (image_picker 1.2.3 facade — USE THESE, do not read ~/.pub-cache)
- The FACADE `ImagePicker` (package:image_picker/image_picker.dart) exposes:
  - `Future<XFile?> pickImage({required ImageSource source, double? maxWidth, double? maxHeight,
    int? imageQuality, CameraDevice preferredCameraDevice = CameraDevice.rear,
    bool requestFullMetadata = true})`
  - `Future<LostDataResponse> retrieveLostData()` — NOT deprecated on the facade.
  - `LostDataResponse({XFile? file, List<XFile>? files, PlatformException? exception,
    RetrieveType? type})` and `LostDataResponse.empty()` both exist.
- The service under test already accepts `CameraVisionService({ImagePicker? picker,
  Duration captureTimeout = const Duration(seconds: 25)})` — inject the mock here.

## Fix (target file: test/data/datasources/tools/chat/camera_vision_service_test.dart ONLY)
Switch from platform-interface mocking to FACADE mocking (the approach of the previous revision
of this file — mock the `ImagePicker` object injected via the constructor):
1. Delete the `image_picker_platform_interface` import (line 11) and the `dart:typed_data`
   import (line 3). KEEP `package:image_picker/image_picker.dart` (it re-exports
   LostDataResponse, ImageSource, CameraDevice, XFile).
2. Replace `_MockImagePickerPlatform extends Mock implements ImagePickerPlatform` with
   `MockImagePicker extends Mock implements ImagePicker` (and the `_MockXFile` class stays).
3. In setUp: `mockPicker = MockImagePicker();` and
   `service = CameraVisionService(picker: mockPicker, captureTimeout: Duration(milliseconds: 100));`
   (drop `ImagePickerPlatform.instance = platform`).
4. Replace the retrieveLostData stub with:
   ```dart
   when(() => mockPicker.retrieveLostData()).thenAnswer((_) async {
     callLog.add('retrieveLostData');
     if (retrieveResponses.isEmpty) {
       return LostDataResponse.empty();
     }
     return retrieveResponses.removeAt(0);
   });
   ```
   and the 'never throws on internal error' case with
   `when(() => mockPicker.retrieveLostData()).thenThrow(Exception('boom'));`
5. Replace the pickImage stub (helper `stubPickImage`) with a stub on the facade signature:
   `when(() => mockPicker.pickImage(source: source, maxWidth: 1024, maxHeight: 1024,
   imageQuality: 80)).thenAnswer(...)` — same body (callLog/throw/hang/file). The success-case
   `verify(...)` calls (if any reference platform) must be updated to mockPicker.
6. `verifyNever(() => platform.retrieveLostData())` -> `verifyNever(() => mockPicker.retrieveLostData())`.
7. All OTHER test cases and assertions stay exactly as written (they are correct).
8. Remove any now-unused imports/variables; ensure `platform`, `retrieveResponses`, `callLog`
   references are consistent.

Do NOT touch any other file. Do NOT read ~/.pub-cache.

## Definition of Done
- Run: flutter analyze  (0 issues on the WHOLE repo — do not exclude other files' errors; if
  errors appear in files you did not touch, report them verbatim, do not fix them)
- Run: flutter test test/data/datasources/tools/chat/camera_vision_service_test.dart (100% pass)
- Report the REAL tail output of both commands.
- Never prefix flutter with flock (wrapper already locks; nested flock deadlocks).
