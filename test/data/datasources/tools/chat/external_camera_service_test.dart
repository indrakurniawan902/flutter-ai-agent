import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ffi_uvc/flutter_ffi_uvc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/external_camera_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/external_camera_service.dart';

class MockUvcCamera extends Mock implements UvcCamera {}

UvcCameraMode _mode({
  int width = 1280,
  int height = 720,
  int fps = 30,
  String formatName = 'MJPEG',
}) => UvcCameraMode(
  frameFormat: 1,
  formatName: formatName,
  width: width,
  height: height,
  fps: fps,
);

UvcAutoPreviewResult _autoResult({
  required bool success,
  UvcCameraMode? mode,
  int nativeErrorCode = 0,
  String? lastError,
}) => UvcAutoPreviewResult(
  attempts: <UvcPreviewStartResult>[
    UvcPreviewStartResult(
      mode: mode ?? _mode(),
      success: success,
      validFrameCount: success ? 3 : 0,
      consecutiveValidFrames: success ? 3 : 0,
      errorCount: success ? 0 : 1,
      elapsed: const Duration(milliseconds: 50),
      lastError: lastError,
      nativeErrorCode: nativeErrorCode,
    ),
  ],
);

UvcUsbDevice _device({
  int deviceId = 7,
  String deviceName = 'usb-0000:00:14.0-1',
  int vendorId = 0x2bc5,
  int productId = 0x0609,
  String productName = 'USB Camera',
  String manufacturerName = 'ACME',
  String serialNumber = 'SN-42',
  bool hasPermission = true,
}) => UvcUsbDevice(
  deviceId: deviceId,
  deviceName: deviceName,
  vendorId: vendorId,
  productId: productId,
  productName: productName,
  manufacturerName: manufacturerName,
  serialNumber: serialNumber,
  hasPermission: hasPermission,
);

void main() {
  late MockUvcCamera mockCamera;
  late ExternalCameraService service;

  setUpAll(() {
    registerFallbackValue(_mode());
  });

  setUp(() {
    mockCamera = MockUvcCamera();
    service = ExternalCameraService(cameraFactory: () => mockCamera);
  });

  group('openDevice', () {
    test('1. awaits permission BEFORE openUsbDevice and returns streaming mode', () async {
      final callOrder = <String>[];
      when(() => mockCamera.openUsbDevice(7)).thenAnswer((_) async {
        callOrder.add('openUsbDevice');
      });
      when(() => mockCamera.startPreviewAuto()).thenAnswer((_) async {
        callOrder.add('startPreviewAuto');
        return _autoResult(success: true, mode: _mode(width: 1920, height: 1080, fps: 25));
      });

      final result = await service.openDevice(
        7,
        ensureCameraPermission: () async {
          callOrder.add('permission');
          return true;
        },
      );

      expect(callOrder, ['permission', 'openUsbDevice', 'startPreviewAuto']);
      expect(result, isA<Right<Failure, ExternalCameraPreviewMode>>());
      result.fold(
        (failure) => fail('Expected Right'),
        (mode) {
          expect(mode.width, 1920);
          expect(mode.height, 1080);
          expect(mode.fps, 25);
          expect(mode.formatName, 'MJPEG');
        },
      );
    });

    test('2. returns PermissionFailure and never opens when permission is denied', () async {
      final result = await service.openDevice(
        7,
        ensureCameraPermission: () async => false,
      );

      expect(result, isA<Left<Failure, ExternalCameraPreviewMode>>());
      result.fold(
        (failure) => expect(failure, isA<PermissionFailure>()),
        (_) => fail('Expected Left'),
      );
      verifyNever(() => mockCamera.openUsbDevice(any()));
      verifyNever(() => mockCamera.startPreviewAuto());
    });

    test('3a. UvcErrorCode.access maps to PermissionFailure', () async {
      when(() => mockCamera.openUsbDevice(7)).thenThrow(
        const UvcException(code: UvcErrorCode.access, message: 'access denied'),
      );

      final result = await service.openDevice(
        7,
        ensureCameraPermission: () async => true,
      );

      result.fold(
        (failure) => expect(failure, isA<PermissionFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('3b. UvcErrorCode.busy maps to CameraBusyFailure', () async {
      when(() => mockCamera.openUsbDevice(7)).thenThrow(
        const UvcException(code: UvcErrorCode.busy),
      );

      final result = await service.openDevice(
        7,
        ensureCameraPermission: () async => true,
      );

      result.fold(
        (failure) => expect(failure, isA<CameraBusyFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('3c. UvcErrorCode.timeout maps to CameraTimeoutFailure', () async {
      when(() => mockCamera.openUsbDevice(7)).thenThrow(
        const UvcException(code: UvcErrorCode.timeout),
      );

      final result = await service.openDevice(
        7,
        ensureCameraPermission: () async => true,
      );

      result.fold(
        (failure) => expect(failure, isA<CameraTimeoutFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('3d. UvcErrorCode.noDevice maps to ServerFailure with [camera_error]', () async {
      when(() => mockCamera.openUsbDevice(7)).thenThrow(
        const UvcException(code: UvcErrorCode.noDevice, message: 'gone'),
      );

      final result = await service.openDevice(
        7,
        ensureCameraPermission: () async => true,
      );

      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, startsWith('[camera_error]'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('3e. PlatformException permission_denied maps to PermissionFailure', () async {
      when(() => mockCamera.openUsbDevice(7)).thenThrow(
        PlatformException(code: 'permission_denied', message: 'USB denied'),
      );

      final result = await service.openDevice(
        7,
        ensureCameraPermission: () async => true,
      );

      result.fold(
        (failure) => expect(failure, isA<PermissionFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('3f. plain Exception maps to ServerFailure with [camera_error]', () async {
      when(() => mockCamera.openUsbDevice(7)).thenThrow(Exception('boom'));

      final result = await service.openDevice(
        7,
        ensureCameraPermission: () async => true,
      );

      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, startsWith('[camera_error]'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('3g. failed startPreviewAuto maps native code and closes the device', () async {
      when(() => mockCamera.openUsbDevice(7)).thenAnswer((_) async {});
      when(() => mockCamera.startPreviewAuto()).thenAnswer(
        (_) async => _autoResult(
          success: false,
          nativeErrorCode: UvcErrorCode.busy.nativeValue,
          lastError: 'resource busy',
        ),
      );
      when(() => mockCamera.closeUsbDevice()).thenAnswer((_) async {});

      final result = await service.openDevice(
        7,
        ensureCameraPermission: () async => true,
      );

      result.fold(
        (failure) => expect(failure, isA<CameraBusyFailure>()),
        (_) => fail('Expected Left'),
      );
      verify(() => mockCamera.closeUsbDevice()).called(1);
    });
  });

  group('capture', () {
    test('4. encodes the JPEG bytes as raw base64', () async {
      final bytes = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);
      when(() => mockCamera.listUsbDevices()).thenAnswer(
        (_) async => <UvcUsbDevice>[_device()],
      );
      await service.listDevices();
      when(() => mockCamera.openedDeviceId).thenReturn(7);
      when(() => mockCamera.takePicture(quality: 90)).thenReturn(
        UvcStillPicture(width: 640, height: 480, jpegBytes: bytes),
      );

      final result = await service.capture();

      expect(result, isA<Right<Failure, ExternalCameraFrame>>());
      result.fold(
        (failure) => fail('Expected Right'),
        (frame) {
          expect(frame.width, 640);
          expect(frame.height, 480);
          expect(frame.base64Jpeg, base64Encode(bytes));
          expect(frame.base64Jpeg, isNot(startsWith('data:')));
        },
      );
    });

    test('5. null takePicture maps to ServerFailure with [camera_error]', () async {
      when(() => mockCamera.listUsbDevices()).thenAnswer(
        (_) async => <UvcUsbDevice>[_device()],
      );
      await service.listDevices();
      when(() => mockCamera.openedDeviceId).thenReturn(7);
      when(() => mockCamera.takePicture(quality: 90)).thenReturn(null);

      final result = await service.capture();

      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, startsWith('[camera_error]'));
        },
        (_) => fail('Expected Left'),
      );
    });

    test('6. no open device maps to ServerFailure without calling takePicture', () async {
      final result = await service.capture();

      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, startsWith('[camera_error]'));
        },
        (_) => fail('Expected Left'),
      );
      verifyNever(() => mockCamera.takePicture(quality: any(named: 'quality')));
    });
  });

  group('listDevices', () {
    test('7. maps every device field and displayName', () async {
      when(() => mockCamera.listUsbDevices()).thenAnswer(
        (_) async => <UvcUsbDevice>[
          _device(
            deviceId: 9,
            deviceName: 'usb-slot-3',
            vendorId: 0x2bc5,
            productId: 0x0609,
            productName: 'HD Cam',
            manufacturerName: 'ACME',
            serialNumber: 'SN-42',
            hasPermission: true,
          ),
        ],
      );

      final result = await service.listDevices();

      result.fold(
        (failure) => fail('Expected Right'),
        (devices) {
          expect(devices, hasLength(1));
          final device = devices.single;
          expect(device.deviceId, 9);
          expect(device.name, 'HD Cam');
          expect(device.vendorId, 0x2bc5);
          expect(device.productId, 0x0609);
          expect(device.manufacturer, 'ACME');
          expect(device.serialNumber, 'SN-42');
          expect(device.hasPermission, isTrue);
          expect(device.displayName, 'HD Cam (2bc5:609)');
        },
      );
    });

    test('7b. falls back to deviceName when productName is empty', () async {
      when(() => mockCamera.listUsbDevices()).thenAnswer(
        (_) async => <UvcUsbDevice>[_device(productName: '')],
      );

      final result = await service.listDevices();

      result.fold(
        (failure) => fail('Expected Right'),
        (devices) => expect(devices.single.name, 'usb-0000:00:14.0-1'),
      );
    });
  });

  group('deviceEvents', () {
    test('8. maps a detached plugin event with its device', () async {
      when(() => mockCamera.listUsbDevices()).thenAnswer(
        (_) async => <UvcUsbDevice>[_device()],
      );
      final event = UvcDeviceEvent(
        type: UvcDeviceEventType.detached,
        device: _device(deviceId: 11, productName: 'Rear Cam'),
      );
      when(() => mockCamera.deviceEvents).thenAnswer(
        (_) => Stream<UvcDeviceEvent>.value(event),
      );

      await service.listDevices();
      final mapped = await service.deviceEvents.first;

      expect(mapped.type, ExternalCameraDeviceEventType.detached);
      expect(mapped.device.deviceId, 11);
      expect(mapped.device.name, 'Rear Cam');
    });
  });

  group('dispose', () {
    test('9. is idempotent and disposes the camera once', () async {
      when(() => mockCamera.listUsbDevices()).thenAnswer(
        (_) async => <UvcUsbDevice>[_device()],
      );
      when(() => mockCamera.dispose()).thenAnswer((_) async {});

      await service.listDevices();
      await service.dispose();
      await service.dispose();

      verify(() => mockCamera.dispose()).called(1);
    });

    test('9b. is safe when no camera was ever created', () async {
      await service.dispose();
      await service.dispose();
    });
  });
}
