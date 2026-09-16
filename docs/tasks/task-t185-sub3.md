# Task T18.5 Sub-task 3: ChatScreen initState lost-capture recovery and widget test

## Target Files (ONLY these 2 files)
- `lib/presentation/screen/chat/chat_screen.dart`
- `test/presentation/screen/chat/chat_screen_attachment_test.dart`

## Files to NOT Touch
- `lib/common/failure.dart`
- `lib/domain/tools/chat/camera_vision_service.dart`
- `lib/data/datasources/tools/chat/camera_vision_service.dart`
- `android/`
- Any other files.

## Context & Rules
- Clean Architecture: Cubits and screens live in presentation.
- When an Activity recreates during an external camera round-trip, the app restarts/resumes and `ChatScreen.initState()` runs.
- `CameraVisionServiceBase.recoverLostCapture()` recovers any lost capture returned by `ImagePicker().retrieveLostData()`.
- If recovered, `ChatScreen` stages it as an attachment (`ChatAttachment`) so the user's photo is not lost.

## Goal

### 1. `lib/presentation/screen/chat/chat_screen.dart`
- In `initState()`, right after resolving `_cameraVisionService`:
  Call `_recoverLostCameraCapture();`
- Add method `Future<void> _recoverLostCameraCapture() async`:
  ```dart
  Future<void> _recoverLostCameraCapture() async {
    final camera = _cameraVisionService;
    if (camera == null) return;
    try {
      final result = await camera.recoverLostCapture();
      result.fold(
        (_) => null,
        (base64Data) {
          if (base64Data != null && base64Data.isNotEmpty && mounted) {
            _setStagedAttachment(
              ChatAttachment(
                filename: 'photo.jpg',
                type: ChatAttachmentType.image,
                mimeType: 'image/jpeg',
                base64Data: base64Data,
              ),
            );
          }
        },
      );
    } catch (_) {}
  }
  ```

### 2. `test/presentation/screen/chat/chat_screen_attachment_test.dart`
- In `setUp`, stub `recoverLostCapture()` with a default empty response:
  ```dart
  when(() => mockCameraService.recoverLostCapture())
      .thenAnswer((_) async => const Right(null));
  ```
- Add a widget test in `group('ChatScreen - Attachment UX')`:
  ```dart
  testWidgets(
    'surfaces recovered lost-data file as staged attachment on init',
    (tester) async {
      when(() => mockCameraService.recoverLostCapture())
          .thenAnswer((_) async => Right(galleryBase64));

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_attachment_chip')), findsOneWidget);
      expect(find.text('photo.jpg'), findsOneWidget);
      verify(() => mockCameraService.recoverLostCapture()).called(1);
    },
  );
  ```

## Definition of Done (DoD)
- Run: flutter analyze (0 issues)
- Run: flutter test test/presentation/screen/chat/chat_screen_attachment_test.dart (100% pass)
- Run: sh tool/check_layout.sh (LAYOUT OK)
- Report real command outputs in your response.
