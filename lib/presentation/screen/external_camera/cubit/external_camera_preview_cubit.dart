import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/external_camera_service.dart';
import 'package:flutter_ai_agent/presentation/screen/external_camera/cubit/external_camera_preview_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Drives the external UVC preview screen: enumeration, device open, texture
/// attach, capture, and USB attach/detach recovery.
///
/// Constructed at the widget level (cubits are not registered in the service
/// locator in this repo). The injected [ExternalCameraServiceBase] is a shared
/// lazy singleton owned by the service locator, so [close] must release only
/// the texture and USB device this cubit opened, never the service itself.
class ExternalCameraPreviewCubit extends Cubit<ExternalCameraPreviewState> {
  final ExternalCameraServiceBase _service;

  /// Permission UI belongs to the presentation layer; the cubit only forwards
  /// this callback so the service can gate `openUsbDevice` behind the app's
  /// single rationale flow.
  final Future<bool> Function() _ensureCameraPermission;

  late final StreamSubscription<ExternalCameraDeviceEvent> _deviceEventsSub;

  ExternalCameraPreviewCubit({
    required ExternalCameraServiceBase service,
    required Future<bool> Function() ensureCameraPermission,
  })  : _service = service,
        _ensureCameraPermission = ensureCameraPermission,
        super(const ExternalCameraPreviewState()) {
    _deviceEventsSub = _service.deviceEvents.listen(_handleDeviceEvent);
  }

  /// Enumerates UVC devices and, when at least one is present, opens the first.
  Future<void> loadDevices() async {
    if (isClosed) return;
    emit(state.copyWith(
      status: ExternalCameraPreviewStatus.loading,
      clearMessage: true,
    ));

    final Either<Failure, List<ExternalCameraDevice>> result =
        await _guard(_service.listDevices);
    if (isClosed) return;

    final Failure? failure = result.fold((f) => f, (_) => null);
    if (failure != null) {
      emit(state.copyWith(
        status: ExternalCameraPreviewStatus.error,
        message: failure.message,
      ));
      return;
    }

    final List<ExternalCameraDevice> devices =
        result.getOrElse(() => const <ExternalCameraDevice>[]);
    if (devices.isEmpty) {
      // An empty enumeration is terminal: the screen must never keep showing a
      // spinner for a camera that cannot appear until the user plugs one in.
      emit(state.copyWith(
        status: ExternalCameraPreviewStatus.noDevice,
        devices: const [],
        message: 'No UVC camera is attached.',
      ));
      return;
    }

    emit(state.copyWith(devices: devices));
    await startPreview();
  }

  /// Opens the first known device and wires its stream to a Flutter texture.
  Future<void> startPreview() async {
    if (isClosed) return;

    if (state.devices.isEmpty) {
      emit(state.copyWith(status: ExternalCameraPreviewStatus.noDevice));
      return;
    }

    final ExternalCameraDevice device = state.devices.first;
    emit(state.copyWith(
      status: ExternalCameraPreviewStatus.starting,
      clearMessage: true,
    ));

    final Either<Failure, ExternalCameraPreviewMode> openResult = await _guard(
      () => _service.openDevice(
        device.deviceId,
        ensureCameraPermission: _ensureCameraPermission,
      ),
    );
    if (isClosed) return;

    final ExternalCameraPreviewMode? mode = openResult.fold(
      (failure) {
        // A denied permission is a distinct, actionable state; any other
        // failure is a generic error. Matching on type keeps the UI decision
        // independent of the failure message wording.
        emit(state.copyWith(
          status: failure is PermissionFailure
              ? ExternalCameraPreviewStatus.permissionDenied
              : ExternalCameraPreviewStatus.error,
          message: failure.message,
        ));
        return null;
      },
      (negotiated) => negotiated,
    );
    if (isClosed || mode == null) return;

    emit(state.copyWith(
      status: ExternalCameraPreviewStatus.starting,
      mode: mode,
    ));

    final Either<Failure, int> textureResult =
        await _guard(_service.createPreviewTexture);
    if (isClosed) return;

    final int? textureId = textureResult.fold(
      (failure) {
        emit(state.copyWith(
          status: ExternalCameraPreviewStatus.error,
          message: failure.message,
        ));
        return null;
      },
      (id) => id,
    );
    if (isClosed || textureId == null) return;

    final Either<Failure, void> attachResult = await _guard(
      () => _service.attachPreviewTexture(
        textureId,
        width: mode.width,
        height: mode.height,
      ),
    );
    if (isClosed) return;

    final Failure? attachFailure =
        attachResult.fold((f) => f, (_) => null);
    if (attachFailure != null) {
      // The texture was created but never attached, so nothing else will ever
      // dispose it; release it here or it leaks a Flutter texture slot.
      await _releaseTexture(textureId);
      if (isClosed) return;
      emit(state.copyWith(
        status: ExternalCameraPreviewStatus.error,
        message: attachFailure.message,
      ));
      return;
    }

    emit(state.copyWith(
      status: ExternalCameraPreviewStatus.previewing,
      openedDeviceId: device.deviceId,
      deviceName: device.name,
      textureId: textureId,
    ));
  }

  /// Re-runs enumeration; used by the refresh button and the retry-permission
  /// button so both share one recovery path.
  Future<void> refresh() => loadDevices();

  /// Captures a still from the live preview.
  Future<void> capture({int quality = 90}) async {
    if (isClosed) return;
    if (state.status != ExternalCameraPreviewStatus.previewing) return;

    emit(state.copyWith(isCapturing: true));

    final Either<Failure, ExternalCameraFrame> result =
        await _guard(() => _service.capture(quality: quality));
    if (isClosed) return;

    final ExternalCameraFrame? frame = result.fold(
      (failure) {
        emit(state.copyWith(
          status: ExternalCameraPreviewStatus.captureFailed,
          message: failure.message,
          isCapturing: false,
        ));
        return null;
      },
      (captured) => captured,
    );
    if (isClosed || frame == null) return;

    emit(state.copyWith(
      status: ExternalCameraPreviewStatus.captured,
      lastCapture: frame,
      isCapturing: false,
    ));
  }

  Future<void> _handleDeviceEvent(ExternalCameraDeviceEvent event) async {
    if (isClosed) return;

    if (event.type == ExternalCameraDeviceEventType.detached) {
      if (event.device.deviceId == state.openedDeviceId) {
        await _releaseTexture(state.textureId);
        try {
          await _service.closeDevice();
        } catch (_) {}
        if (isClosed) return;
        emit(state.copyWith(
          status: ExternalCameraPreviewStatus.deviceDetached,
          clearTextureId: true,
          clearMode: true,
          clearOpenedDeviceId: true,
          message: 'The external camera was disconnected.',
        ));
        return;
      }
      // A detach for a device this cubit does not own only matters while idle;
      // re-scan so the device list stays honest.
      if (state.openedDeviceId == null) {
        await loadDevices();
      }
      return;
    }

    // Re-enumerate only from a terminal empty state; reacting while previewing
    // would drive an endless load/preview loop on every attach event.
    if (state.status == ExternalCameraPreviewStatus.noDevice ||
        state.status == ExternalCameraPreviewStatus.deviceDetached) {
      await loadDevices();
    }
  }

  /// Best-effort texture release: the native plugin may already be gone.
  Future<void> _releaseTexture(int? textureId) async {
    if (textureId == null) return;
    try {
      await _service.disposePreviewTexture(textureId);
    } catch (_) {}
  }

  /// Runs [call], converting a thrown exception into a [ServerFailure] so no
  /// public cubit method ever lets one escape to the UI.
  Future<Either<Failure, T>> _guard<T>(
    Future<Either<Failure, T>> Function() call,
  ) async {
    try {
      return await call();
    } catch (e) {
      return Left(ServerFailure('[camera_error] $e'));
    }
  }

  @override
  Future<void> close() async {
    await _deviceEventsSub.cancel();
    await _releaseTexture(state.textureId);
    try {
      await _service.closeDevice();
    } catch (_) {}
    return super.close();
  }
}
