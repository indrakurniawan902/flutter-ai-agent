import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

/// Image source selection for camera_take_photo.
enum CameraSource { camera, gallery }

/// Inner capture window for [CameraVisionServiceBase.takePhoto].
/// The registry's outer bound for `camera_take_photo`
/// ([ToolRegistry.longWindowToolTimeout], 25s) must stay strictly greater, and
/// the whole call must stay under the device bridge's 30s call budget, so a
/// slow capture surfaces as [CameraTimeoutFailure] instead of a registry timeout.
const Duration kCameraCaptureTimeout = Duration(seconds: 20);

/// Abstraction for camera / gallery image capture returning base64.
///
/// Tools:
///  - camera_take_photo: Tier 2 (permission-gated)
abstract class CameraVisionServiceBase {
  /// Captures or picks an image, compresses to max 1024×1024 JPEG 80%,
  /// and returns the base64-encoded payload.
  Future<Either<Failure, String>> takePhoto({
    required CameraSource source,
  });

  /// Recovers a capture lost to an Activity recreation (image_picker lost-data API).
  /// Right(null) when there is nothing to recover; Right(base64) on recovered capture;
  /// Left(CameraLostResultFailure) when recovery itself failed. Never throws.
  Future<Either<Failure, String?>> recoverLostCapture();
}
