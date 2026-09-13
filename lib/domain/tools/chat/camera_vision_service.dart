import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

/// Image source selection for camera_take_photo.
enum CameraSource { camera, gallery }

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
