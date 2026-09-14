import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

/// A UVC-capable USB camera attached to the device.
class ExternalCameraDevice {
  const ExternalCameraDevice({
    required this.deviceId,
    required this.name,
    required this.vendorId,
    required this.productId,
    this.manufacturer = '',
    this.serialNumber = '',
    this.hasPermission = false,
  });

  final int deviceId;
  final String name;
  final int vendorId;
  final int productId;
  final String manufacturer;
  final String serialNumber;
  final bool hasPermission;

  String get displayName =>
      '$name (${vendorId.toRadixString(16)}:${productId.toRadixString(16)})';
}

/// The preview mode that is actually streaming.
class ExternalCameraPreviewMode {
  const ExternalCameraPreviewMode({
    required this.width,
    required this.height,
    required this.fps,
    this.formatName = '',
  });

  final int width;
  final int height;
  final int fps;
  final String formatName;
}

/// A single still frame encoded to JPEG and base64-encoded (raw, no data: prefix).
class ExternalCameraFrame {
  const ExternalCameraFrame({
    required this.width,
    required this.height,
    required this.base64Jpeg,
  });

  final int width;
  final int height;
  final String base64Jpeg;
}

/// USB attach/detach lifecycle kind for a UVC-capable device.
enum ExternalCameraDeviceEventType { attached, detached }

/// A USB attach/detach event carrying the device it concerns.
class ExternalCameraDeviceEvent {
  const ExternalCameraDeviceEvent({required this.type, required this.device});

  final ExternalCameraDeviceEventType type;
  final ExternalCameraDevice device;
}

/// Current device / preview state of the external camera session.
class ExternalCameraStatus {
  const ExternalCameraStatus({
    required this.isDeviceOpen,
    required this.isPreviewing,
    this.mode,
    this.openedDeviceId,
    this.deviceName = '',
  });

  const ExternalCameraStatus.closed()
    : isDeviceOpen = false,
      isPreviewing = false,
      mode = null,
      openedDeviceId = null,
      deviceName = '';

  final bool isDeviceOpen;
  final bool isPreviewing;
  final ExternalCameraPreviewMode? mode;
  final int? openedDeviceId;
  final String deviceName;
}

/// Abstraction over the UVC external camera engine (flutter_ffi_uvc).
///
/// Tools:
///  - external_camera_*: Tier 2 (permission-gated)
abstract class ExternalCameraServiceBase {
  /// Lists UVC-capable USB cameras currently attached to the device.
  Future<Either<Failure, List<ExternalCameraDevice>>> listDevices();

  /// Requests the CAMERA runtime permission, then opens [deviceId] over USB and
  /// starts a verified preview stream, returning the mode that is streaming.
  ///
  /// [ensureCameraPermission] is supplied by the caller so the rationale UI stays
  /// in the presentation layer (`PermissionGate.requestWithRationale`). The
  /// implementation MUST await it BEFORE `openUsbDevice`, and MUST return
  /// `PermissionFailure` when it resolves to false. Passing a callback that
  /// returns false is how a headless caller refuses to raise a UI prompt.
  Future<Either<Failure, ExternalCameraPreviewMode>> openDevice(
    int deviceId, {
    required Future<bool> Function() ensureCameraPermission,
  });

  /// Creates a Flutter texture the preview renders into.
  Future<Either<Failure, int>> createPreviewTexture();

  /// Binds the open camera's preview stream to [textureId].
  Future<Either<Failure, void>> attachPreviewTexture(
    int textureId, {
    int? width,
    int? height,
  });

  /// Releases a texture created by [createPreviewTexture].
  Future<Either<Failure, void>> disposePreviewTexture(int textureId);

  /// Encodes the latest preview frame to JPEG and returns it base64-encoded.
  Future<Either<Failure, ExternalCameraFrame>> capture({int quality = 90});

  /// Check-only probe: is the CAMERA runtime permission already granted?
  ///
  /// NEVER raises a prompt. Tools run in headless contexts (gateway RPC, voice
  /// turn) where a permission dialog would hang; they check and return a
  /// readable Failure instead. The user-facing prompt stays on Flames' single
  /// PermissionGate path in the presentation layer.
  Future<bool> isCameraPermissionGranted();

  /// Current device / preview state.
  ExternalCameraStatus get status;

  /// USB attach/detach events for UVC-capable devices.
  Stream<ExternalCameraDeviceEvent> get deviceEvents;

  /// Stops the preview and closes the open USB device. Safe to call when closed.
  Future<void> closeDevice();

  /// Releases the camera session. Safe to call more than once.
  Future<void> dispose();
}
