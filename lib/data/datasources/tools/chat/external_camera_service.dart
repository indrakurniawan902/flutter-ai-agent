import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ffi_uvc/flutter_ffi_uvc.dart';
import 'package:injectable/injectable.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/domain/tools/chat/external_camera_service.dart';

/// Injectable read-only CAMERA permission probe so unit tests never touch a
/// platform channel.
abstract class CameraPermissionProbe {
  Future<bool> isGranted();
}

/// Production probe: `.status` is a pure read and never raises a dialog.
class DefaultCameraPermissionProbe implements CameraPermissionProbe {
  const DefaultCameraPermissionProbe();

  @override
  Future<bool> isGranted() async {
    try {
      return (await Permission.camera.status).isGranted;
    } catch (_) {
      return false;
    }
  }
}

@LazySingleton(as: ExternalCameraServiceBase)
class ExternalCameraService implements ExternalCameraServiceBase {
  ExternalCameraService({
    UvcCamera Function()? cameraFactory,
    CameraPermissionProbe? permissionProbe,
  }) : _createCamera = cameraFactory ?? UvcCamera.new,
       _permissionProbe =
           permissionProbe ?? const DefaultCameraPermissionProbe();

  @factoryMethod
  factory ExternalCameraService.create() => ExternalCameraService();

  final UvcCamera Function() _createCamera;
  final CameraPermissionProbe _permissionProbe;

  UvcCamera? _camera;
  int? _openedDeviceId;
  ExternalCameraPreviewMode? _mode;
  String _deviceName = '';
  List<ExternalCameraDevice> _lastDevices = const <ExternalCameraDevice>[];

  /// The camera is created lazily so constructing this service in a unit test
  /// never touches a platform channel.
  UvcCamera _ensureCamera() => _camera ??= _createCamera();

  ExternalCameraDevice _mapDevice(UvcUsbDevice device) => ExternalCameraDevice(
    deviceId: device.deviceId,
    name: device.productName.isNotEmpty ? device.productName : device.deviceName,
    vendorId: device.vendorId,
    productId: device.productId,
    manufacturer: device.manufacturerName,
    serialNumber: device.serialNumber,
    hasPermission: device.hasPermission,
  );

  ExternalCameraPreviewMode _mapMode(UvcCameraMode mode) =>
      ExternalCameraPreviewMode(
        width: mode.width,
        height: mode.height,
        fps: mode.fps,
        formatName: mode.formatName,
      );

  /// Single source of truth for the native error code -> [Failure] table.
  Failure _failureForCode(UvcErrorCode? code, Object error) {
    switch (code) {
      case UvcErrorCode.access:
        return PermissionFailure(
          FailureMessage.humanize(error, context: 'Camera permission denied'),
        );
      case UvcErrorCode.busy:
        return const CameraBusyFailure();
      case UvcErrorCode.timeout:
        return const CameraTimeoutFailure();
      case UvcErrorCode.noDevice:
      case UvcErrorCode.notFound:
      case UvcErrorCode.invalidDevice:
      case UvcErrorCode.invalidMode:
        return ServerFailure('[camera_error] ${FailureMessage.humanize(error)}');
      default:
        return ServerFailure('[camera_error] ${FailureMessage.humanize(error)}');
    }
  }

  Failure _mapError(Object error) {
    if (error is UvcException) {
      return _failureForCode(error.code, error);
    }
    if (error is PlatformException) {
      final String code = error.code.toLowerCase();
      final String message = (error.message ?? '').toLowerCase();
      if (code.contains('permission') ||
          code.contains('denied') ||
          message.contains('permission') ||
          message.contains('denied')) {
        return PermissionFailure(
          FailureMessage.humanize(error, context: 'Camera permission denied'),
        );
      }
      return ServerFailure('[camera_error] ${FailureMessage.humanize(error)}');
    }
    return ServerFailure('[camera_error] ${FailureMessage.humanize(error)}');
  }

  /// Maps a raw native code from a non-throwing result through the same table.
  Failure _mapErrorFromNativeCode(int nativeCode, String? message) {
    final UvcErrorCode? code = UvcErrorCode.fromNativeValue(nativeCode);
    return _failureForCode(
      code,
      UvcException(
        code: code ?? UvcErrorCode.other,
        nativeCode: nativeCode,
        message: message ?? '',
      ),
    );
  }

  Future<void> _safeCloseDevice() async {
    final UvcCamera? camera = _camera;
    if (camera == null) return;
    try {
      await camera.closeUsbDevice();
    } catch (_) {}
    _openedDeviceId = null;
    _mode = null;
    _deviceName = '';
  }

  @override
  Future<Either<Failure, List<ExternalCameraDevice>>> listDevices() async {
    try {
      final List<UvcUsbDevice> devices = await _ensureCamera().listUsbDevices();
      final List<ExternalCameraDevice> mapped = devices.map(_mapDevice).toList();
      _lastDevices = mapped;
      return Right(mapped);
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, ExternalCameraPreviewMode>> openDevice(
    int deviceId, {
    required Future<bool> Function() ensureCameraPermission,
  }) async {
    try {
      // Flames has exactly one CAMERA permission path (PermissionGate); the
      // caller's callback must resolve before any USB open so a denial never
      // raises a second prompt from the plugin.
      final bool granted = await ensureCameraPermission();
      if (!granted) {
        return const Left(PermissionFailure('Camera permission denied'));
      }

      final UvcCamera camera = _ensureCamera();
      await camera.openUsbDevice(deviceId);
      final UvcAutoPreviewResult result = await camera.startPreviewAuto();
      if (!result.success) {
        await _safeCloseDevice();
        final UvcPreviewStartResult? last = result.attempts.isEmpty
            ? null
            : result.attempts.last;
        return Left(
          _mapErrorFromNativeCode(
            last?.nativeErrorCode ?? 0,
            last?.lastError,
          ),
        );
      }

      _openedDeviceId = deviceId;
      _mode = _mapMode(result.mode!);
      _deviceName = '';
      for (final ExternalCameraDevice device in _lastDevices) {
        if (device.deviceId == deviceId) {
          _deviceName = device.name;
          break;
        }
      }
      return Right(_mode!);
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, int>> createPreviewTexture() async {
    try {
      return Right(await _ensureCamera().createPreviewTexture());
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, void>> attachPreviewTexture(
    int textureId, {
    int? width,
    int? height,
  }) async {
    try {
      await _ensureCamera().attachPreviewTexture(
        textureId,
        width: width,
        height: height,
      );
      return const Right(null);
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, void>> disposePreviewTexture(int textureId) async {
    try {
      await _ensureCamera().disposePreviewTexture(textureId);
      return const Right(null);
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<Either<Failure, ExternalCameraFrame>> capture({
    int quality = 90,
  }) async {
    final UvcCamera? camera = _camera;
    if (camera == null || camera.openedDeviceId == null) {
      return const Left(
        ServerFailure('[camera_error] no external camera device is open'),
      );
    }
    try {
      final UvcStillPicture? still = camera.takePicture(quality: quality);
      if (still == null) {
        return const Left(
          ServerFailure('[camera_error] no preview frame available yet'),
        );
      }
      return Right(
        ExternalCameraFrame(
          width: still.width,
          height: still.height,
          base64Jpeg: base64Encode(still.jpegBytes),
        ),
      );
    } catch (e) {
      return Left(_mapError(e));
    }
  }

  @override
  Future<bool> isCameraPermissionGranted() async {
    try {
      return await _permissionProbe.isGranted();
    } catch (_) {
      return false;
    }
  }

  @override
  ExternalCameraStatus get status {
    final UvcCamera? camera = _camera;
    if (camera == null) return const ExternalCameraStatus.closed();
    final int? deviceId = camera.openedDeviceId ?? _openedDeviceId;
    return ExternalCameraStatus(
      isDeviceOpen: deviceId != null,
      isPreviewing: camera.isPreviewing,
      mode: _mode,
      openedDeviceId: deviceId,
      deviceName: _deviceName,
    );
  }

  @override
  Stream<ExternalCameraDeviceEvent> get deviceEvents {
    final UvcCamera? camera = _camera;
    if (camera == null) {
      return const Stream<ExternalCameraDeviceEvent>.empty();
    }
    return camera.deviceEvents.map(
      (UvcDeviceEvent event) => ExternalCameraDeviceEvent(
        type: event.type == UvcDeviceEventType.attached
            ? ExternalCameraDeviceEventType.attached
            : ExternalCameraDeviceEventType.detached,
        device: _mapDevice(event.device),
      ),
    );
  }

  @override
  Future<void> closeDevice() async {
    await _safeCloseDevice();
  }

  @override
  Future<void> dispose() async {
    final UvcCamera? camera = _camera;
    if (camera == null) return;
    _camera = null;
    _openedDeviceId = null;
    _mode = null;
    _deviceName = '';
    try {
      await camera.dispose();
    } catch (_) {}
  }
}
