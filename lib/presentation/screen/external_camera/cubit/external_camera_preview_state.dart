import 'package:equatable/equatable.dart';
import 'package:flutter_ai_agent/domain/tools/chat/external_camera_service.dart';

/// Lifecycle of the external camera preview screen.
enum ExternalCameraPreviewStatus {
  loading,
  noDevice,
  permissionDenied,
  starting,
  previewing,
  captured,
  captureFailed,
  deviceDetached,
  error,
}

/// Immutable state for `ExternalCameraPreviewCubit`.
///
/// Every nullable field needs an explicit clear flag in [copyWith] because
/// `null` as an argument is indistinguishable from "leave unchanged".
class ExternalCameraPreviewState extends Equatable {
  /// Drives which pane the screen renders; terminal states must never leave a
  /// spinner behind.
  final ExternalCameraPreviewStatus status;

  /// UVC devices found by the last enumeration.
  final List<ExternalCameraDevice> devices;

  /// Device whose USB handle the cubit currently owns.
  final int? openedDeviceId;

  /// Friendly name of [openedDeviceId] for the preview header.
  final String deviceName;

  /// Mode the native stream actually negotiated, not the requested one.
  final ExternalCameraPreviewMode? mode;

  /// Flutter texture the preview renders into.
  final int? textureId;

  /// Most recent successful capture, kept so the screen can still show it once
  /// the status moves on.
  final ExternalCameraFrame? lastCapture;

  /// Human-readable detail for the current non-happy status.
  final String? message;

  /// True between the capture request and its result; blocks double taps.
  final bool isCapturing;

  const ExternalCameraPreviewState({
    this.status = ExternalCameraPreviewStatus.loading,
    this.devices = const [],
    this.openedDeviceId,
    this.deviceName = '',
    this.mode,
    this.textureId,
    this.lastCapture,
    this.message,
    this.isCapturing = false,
  });

  ExternalCameraPreviewState copyWith({
    ExternalCameraPreviewStatus? status,
    List<ExternalCameraDevice>? devices,
    int? openedDeviceId,
    String? deviceName,
    ExternalCameraPreviewMode? mode,
    int? textureId,
    ExternalCameraFrame? lastCapture,
    String? message,
    bool? isCapturing,
    bool clearOpenedDeviceId = false,
    bool clearMode = false,
    bool clearTextureId = false,
    bool clearLastCapture = false,
    bool clearMessage = false,
  }) {
    return ExternalCameraPreviewState(
      status: status ?? this.status,
      devices: devices ?? this.devices,
      openedDeviceId:
          clearOpenedDeviceId ? null : (openedDeviceId ?? this.openedDeviceId),
      deviceName: deviceName ?? this.deviceName,
      mode: clearMode ? null : (mode ?? this.mode),
      textureId: clearTextureId ? null : (textureId ?? this.textureId),
      lastCapture: clearLastCapture ? null : (lastCapture ?? this.lastCapture),
      message: clearMessage ? null : (message ?? this.message),
      isCapturing: isCapturing ?? this.isCapturing,
    );
  }

  @override
  List<Object?> get props => [
    status,
    devices,
    openedDeviceId,
    deviceName,
    mode,
    textureId,
    lastCapture,
    message,
    isCapturing,
  ];
}
