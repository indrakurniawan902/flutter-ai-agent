import 'package:flutter/foundation.dart';

/// Clean Architecture interface for controlling the QR camera scanner hardware.
abstract class QrScannerControllerBase {
  /// Notifier for whether the camera flashlight/torch is currently turned on.
  ValueListenable<bool> get isTorchOn;

  /// Toggles the flashlight / torch on or off.
  Future<void> toggleTorch();

  /// Starts the camera stream.
  Future<void> start();

  /// Stops the camera stream.
  Future<void> stop();

  /// Disposes controller resources.
  void dispose();
}
