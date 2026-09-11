import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/camera_vision_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

class MockImagePicker extends Mock implements ImagePicker {}

class MockXFile extends Mock implements XFile {}

void main() {
  late MockImagePicker mockPicker;
  late CameraVisionService service;

  setUp(() {
    mockPicker = MockImagePicker();
    service = CameraVisionService(picker: mockPicker);
  });

  group('takePhoto', () {
    test('returns base64 string when camera captures successfully', () async {
      // Arrange
      final fakeBytes = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      final mockFile = MockXFile();

      when(
        () => mockPicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).thenAnswer((_) async => mockFile);

      when(() => mockFile.readAsBytes()).thenAnswer(
        (_) async => fakeBytes,
      );

      // Act
      final result = await service.takePhoto(source: CameraSource.camera);

      // Assert
      expect(result, isA<Right<Failure, String>>());
      final base64Result = result.getOrElse(() => '');
      expect(base64Result, base64Encode(fakeBytes));

      verify(
        () => mockPicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).called(1);
      verify(() => mockFile.readAsBytes()).called(1);
    });

    test('returns base64 string when gallery picks successfully', () async {
      // Arrange
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

      when(() => mockFile.readAsBytes()).thenAnswer(
        (_) async => fakeBytes,
      );

      // Act
      final result = await service.takePhoto(source: CameraSource.gallery);

      // Assert
      expect(result, isA<Right<Failure, String>>());
      final base64Result = result.getOrElse(() => '');
      expect(base64Result, base64Encode(fakeBytes));

      verify(
        () => mockPicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).called(1);
    });

    test('returns PermissionFailure when user cancels (null XFile)', () async {
      // Arrange
      when(
        () => mockPicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).thenAnswer((_) async => null);

      // Act
      final result = await service.takePhoto(source: CameraSource.camera);

      // Assert
      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<PermissionFailure>());
          expect(failure.message, contains('cancelled'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns ServerFailure when readAsBytes throws', () async {
      // Arrange
      final mockFile = MockXFile();

      when(
        () => mockPicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).thenAnswer((_) async => mockFile);

      when(() => mockFile.readAsBytes()).thenThrow(
        Exception('File read error'),
      );

      // Act
      final result = await service.takePhoto(source: CameraSource.camera);

      // Assert
      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Camera error'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns ServerFailure when pickImage throws', () async {
      // Arrange
      when(
        () => mockPicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).thenThrow(Exception('Platform error'));

      // Act
      final result = await service.takePhoto(source: CameraSource.gallery);

      // Assert
      expect(result, isA<Left<Failure, String>>());
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Camera error'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('passes correct ImageSource for camera', () async {
      // Arrange
      final fakeBytes = Uint8List.fromList([1, 2, 3]);
      final mockFile = MockXFile();

      when(
        () => mockPicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).thenAnswer((_) async => mockFile);

      when(() => mockFile.readAsBytes()).thenAnswer(
        (_) async => fakeBytes,
      );

      // Act
      await service.takePhoto(source: CameraSource.camera);

      // Assert
      verify(
        () => mockPicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).called(1);
    });

    test('passes correct ImageSource for gallery', () async {
      // Arrange
      final fakeBytes = Uint8List.fromList([1, 2, 3]);
      final mockFile = MockXFile();

      when(
        () => mockPicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).thenAnswer((_) async => mockFile);

      when(() => mockFile.readAsBytes()).thenAnswer(
        (_) async => fakeBytes,
      );

      // Act
      await service.takePhoto(source: CameraSource.gallery);

      // Assert
      verify(
        () => mockPicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).called(1);
    });

    test('returns PermissionFailure when camera permission is denied (camera_access_denied)', () async {
      when(
        () => mockPicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).thenThrow(PlatformException(code: 'camera_access_denied', message: 'User denied camera access'));

      final result = await service.takePhoto(source: CameraSource.camera);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<PermissionFailure>());
          expect(failure.message, contains('Camera permission denied'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns PermissionFailure when gallery permission is denied (photo_access_denied)', () async {
      when(
        () => mockPicker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).thenThrow(PlatformException(code: 'photo_access_denied', message: 'User denied photo access'));

      final result = await service.takePhoto(source: CameraSource.gallery);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<PermissionFailure>());
          expect(failure.message, contains('Photo library permission denied'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('returns PermissionFailure when exception message contains denied/permission', () async {
      when(
        () => mockPicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1024,
          maxHeight: 1024,
          imageQuality: 80,
        ),
      ).thenThrow(PlatformException(code: 'error', message: 'Permission was denied by the user'));

      final result = await service.takePhoto(source: CameraSource.camera);

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<PermissionFailure>());
          expect(failure.message, contains('permission denied'));
        },
        (_) => fail('Expected Left'),
      );
    });
  });
}
