import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

class MockImagePicker extends Mock implements ImagePicker {}

class MockXFile extends Mock implements XFile {}

void main() {
  late MockImagePicker mockPicker;
  late CameraVisionService service;

  setUpAll(() {
    registerFallbackValue(ImageSource.camera);
  });

  setUp(() {
    mockPicker = MockImagePicker();
    service = CameraVisionService(
      picker: mockPicker,
      captureTimeout: const Duration(milliseconds: 100),
    );
    when(() => mockPicker.retrieveLostData()).thenAnswer(
      (_) async => LostDataResponse.empty(),
    );
  });

  group('takePhoto', () {
    test(
      '1. camera capture success: pickImage returns XFile -> Right(base64), retrieveLostData called BEFORE pickImage',
      () async {
        final fakeBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
        final mockFile = MockXFile();
        final callOrder = <String>[];

        when(() => mockPicker.retrieveLostData()).thenAnswer((_) async {
          callOrder.add('retrieveLostData');
          return LostDataResponse.empty();
        });

        when(
          () => mockPicker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 80,
          ),
        ).thenAnswer((_) async {
          callOrder.add('pickImage');
          return mockFile;
        });

        when(() => mockFile.readAsBytes()).thenAnswer((_) async => fakeBytes);

        final result = await service.takePhoto(source: CameraSource.camera);

        expect(result, isA<Right<Failure, String>>());
        expect(result.getOrElse(() => ''), base64Encode(fakeBytes));
        expect(callOrder, ['retrieveLostData', 'pickImage']);
        verify(() => mockPicker.retrieveLostData()).called(1);
        verify(
          () => mockPicker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 80,
          ),
        ).called(1);
      },
    );

    test(
      '2. gallery pick success: pickImage returns XFile -> Right(base64), retrieveLostData NOT called',
      () async {
        final fakeBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 4, 5, 6]);
        final mockFile = MockXFile();

        when(
          () => mockPicker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 80,
          ),
        ).thenAnswer((_) async => mockFile);

        when(() => mockFile.readAsBytes()).thenAnswer((_) async => fakeBytes);

        final result = await service.takePhoto(source: CameraSource.gallery);

        expect(result, isA<Right<Failure, String>>());
        expect(result.getOrElse(() => ''), base64Encode(fakeBytes));
        verifyNever(() => mockPicker.retrieveLostData());
        verify(
          () => mockPicker.pickImage(
            source: ImageSource.gallery,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 80,
          ),
        ).called(1);
      },
    );

    test(
      '3. pre-existing lost data on camera entry: returns Right(base64) immediately without pickImage',
      () async {
        final fakeBytes = Uint8List.fromList([1, 2, 3, 4]);
        final mockFile = MockXFile();

        when(() => mockPicker.retrieveLostData()).thenAnswer(
          (_) async => LostDataResponse(file: mockFile),
        );
        when(() => mockFile.readAsBytes()).thenAnswer((_) async => fakeBytes);

        final result = await service.takePhoto(source: CameraSource.camera);

        expect(result, isA<Right<Failure, String>>());
        expect(result.getOrElse(() => ''), base64Encode(fakeBytes));
        verify(() => mockPicker.retrieveLostData()).called(1);
        verifyNever(
          () => mockPicker.pickImage(
            source: any(named: 'source'),
            maxWidth: any(named: 'maxWidth'),
            maxHeight: any(named: 'maxHeight'),
            imageQuality: any(named: 'imageQuality'),
          ),
        );
      },
    );

    test(
      '4. pickImage returns null, retrieveLostData empty -> Left(CameraCancelledFailure) with camera_cancelled',
      () async {
        when(
          () => mockPicker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 80,
          ),
        ).thenAnswer((_) async => null);

        final result = await service.takePhoto(source: CameraSource.camera);

        expect(result, isA<Left<Failure, String>>());
        result.fold(
          (failure) {
            expect(failure, isA<CameraCancelledFailure>());
            expect(failure.message, contains('camera_cancelled'));
          },
          (_) => fail('Expected Left'),
        );
      },
    );

    test(
      '5. pickImage returns null, retrieveLostData has file -> Right(base64)',
      () async {
        final fakeBytes = Uint8List.fromList([7, 8, 9]);
        final mockFile = MockXFile();
        var callCount = 0;

        when(() => mockPicker.retrieveLostData()).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) return LostDataResponse.empty();
          return LostDataResponse(file: mockFile);
        });

        when(
          () => mockPicker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 80,
          ),
        ).thenAnswer((_) async => null);

        when(() => mockFile.readAsBytes()).thenAnswer((_) async => fakeBytes);

        final result = await service.takePhoto(source: CameraSource.camera);

        expect(result, isA<Right<Failure, String>>());
        expect(result.getOrElse(() => ''), base64Encode(fakeBytes));
      },
    );

    test(
      '6. pickImage returns null, retrieveLostData has exception -> Left(CameraLostResultFailure) with camera_lost_result',
      () async {
        var callCount = 0;
        when(() => mockPicker.retrieveLostData()).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) return LostDataResponse.empty();
          return LostDataResponse(
            exception: PlatformException(
              code: 'crash',
              message: 'camera_lost_result',
            ),
          );
        });

        when(
          () => mockPicker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 80,
          ),
        ).thenAnswer((_) async => null);

        final result = await service.takePhoto(source: CameraSource.camera);

        expect(result, isA<Left<Failure, String>>());
        result.fold(
          (failure) {
            expect(failure, isA<CameraLostResultFailure>());
            expect(failure.message, contains('camera_lost_result'));
          },
          (_) => fail('Expected Left'),
        );
      },
    );

    test(
      '7. pickImage throws PlatformException(already_active), retrieveLostData has file -> Right(base64)',
      () async {
        final fakeBytes = Uint8List.fromList([10, 11, 12]);
        final mockFile = MockXFile();
        var callCount = 0;

        when(() => mockPicker.retrieveLostData()).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) return LostDataResponse.empty();
          return LostDataResponse(file: mockFile);
        });

        when(
          () => mockPicker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 80,
          ),
        ).thenThrow(PlatformException(code: 'already_active'));

        when(() => mockFile.readAsBytes()).thenAnswer((_) async => fakeBytes);

        final result = await service.takePhoto(source: CameraSource.camera);

        expect(result, isA<Right<Failure, String>>());
        expect(result.getOrElse(() => ''), base64Encode(fakeBytes));
      },
    );

    test(
      '8. pickImage throws PlatformException(already_active), retrieveLostData empty -> Left(CameraBusyFailure) with camera_busy',
      () async {
        when(
          () => mockPicker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 80,
          ),
        ).thenThrow(PlatformException(code: 'already_active'));

        final result = await service.takePhoto(source: CameraSource.camera);

        expect(result, isA<Left<Failure, String>>());
        result.fold(
          (failure) {
            expect(failure, isA<CameraBusyFailure>());
            expect(failure.message, contains('camera_busy'));
          },
          (_) => fail('Expected Left'),
        );
      },
    );

    test(
      '9. pickImage throws PlatformException(permissionDenied) -> Left(PermissionFailure)',
      () async {
        when(
          () => mockPicker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 80,
          ),
        ).thenThrow(
          PlatformException(
            code: 'permissionDenied',
            message: 'Camera permission denied',
          ),
        );

        final result = await service.takePhoto(source: CameraSource.camera);

        expect(result, isA<Left<Failure, String>>());
        result.fold(
          (failure) {
            expect(failure, isA<PermissionFailure>());
            expect(failure.message, contains('permission'));
          },
          (_) => fail('Expected Left'),
        );
      },
    );

    test(
      '10. pickImage hangs forever (Completer), captureTimeout expires -> Left(CameraTimeoutFailure) with camera_timeout',
      () async {
        final completer = Completer<XFile?>();

        when(
          () => mockPicker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 80,
          ),
        ).thenAnswer((_) => completer.future);

        final result = await service.takePhoto(source: CameraSource.camera);

        expect(result, isA<Left<Failure, String>>());
        result.fold(
          (failure) {
            expect(failure, isA<CameraTimeoutFailure>());
            expect(failure.message, contains('camera_timeout'));
          },
          (_) => fail('Expected Left'),
        );
      },
    );

    test(
      '11. pickImage throws generic Exception -> Left(ServerFailure) with [camera_error]',
      () async {
        when(
          () => mockPicker.pickImage(
            source: ImageSource.camera,
            maxWidth: 1024,
            maxHeight: 1024,
            imageQuality: 80,
          ),
        ).thenThrow(Exception('Native bridge failure'));

        final result = await service.takePhoto(source: CameraSource.camera);

        expect(result, isA<Left<Failure, String>>());
        result.fold(
          (failure) {
            expect(failure, isA<ServerFailure>());
            expect(failure.message, contains('[camera_error]'));
          },
          (_) => fail('Expected Left'),
        );
      },
    );
  });

  group('recoverLostCapture', () {
    test('12. returns Right(base64) when file present, Right(null) when empty, Left(CameraLostResultFailure) on exception', () async {
      final fakeBytes = Uint8List.fromList([100, 101, 102]);
      final mockFile = MockXFile();

      when(() => mockPicker.retrieveLostData()).thenAnswer(
        (_) async => LostDataResponse(file: mockFile),
      );
      when(() => mockFile.readAsBytes()).thenAnswer((_) async => fakeBytes);

      final withFile = await service.recoverLostCapture();
      expect(withFile, isA<Right<Failure, String?>>());
      expect(withFile.getOrElse(() => null), base64Encode(fakeBytes));

      when(() => mockPicker.retrieveLostData()).thenAnswer(
        (_) async => LostDataResponse.empty(),
      );

      final empty = await service.recoverLostCapture();
      expect(empty, isA<Right<Failure, String?>>());
      expect(empty.getOrElse(() => 'not-null'), isNull);

      when(() => mockPicker.retrieveLostData()).thenAnswer(
        (_) async => LostDataResponse(
          exception: PlatformException(
            code: 'crash',
            message: 'camera_lost_result',
          ),
        ),
      );

      final withException = await service.recoverLostCapture();
      expect(withException, isA<Left<Failure, String?>>());
      withException.fold(
        (failure) {
          expect(failure, isA<CameraLostResultFailure>());
          expect(failure.message, contains('camera_lost_result'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('13. returns Right(null) and never throws if retrieveLostData throws an unexpected Exception', () async {
      when(() => mockPicker.retrieveLostData()).thenThrow(
        Exception('Uncaught platform error'),
      );

      final result = await service.recoverLostCapture();

      expect(result, isA<Right<Failure, String?>>());
      expect(result.getOrElse(() => 'not-null'), isNull);
    });
  });
}
