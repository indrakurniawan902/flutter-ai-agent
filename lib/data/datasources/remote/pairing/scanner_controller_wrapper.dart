import 'package:flutter/foundation.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/qr_scanner_controller.dart';
import 'package:injectable/injectable.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Clean Architecture wrapper for [MobileScannerController].
@LazySingleton(as: QrScannerControllerBase)
class MobileScannerControllerWrapper implements QrScannerControllerBase {
  final MobileScannerController controller;
  final ValueNotifier<bool> _isTorchOnNotifier;

  MobileScannerControllerWrapper({
    @ignoreParam MobileScannerController? controller,
  }) : controller = controller ??
            MobileScannerController(
              formats: const [BarcodeFormat.qrCode],
              detectionSpeed: DetectionSpeed.noDuplicates,
            ),
        _isTorchOnNotifier = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get isTorchOn => _isTorchOnNotifier;

  @override
  Object? get scannerController => controller;

  @override
  Future<void> toggleTorch() async {
    try {
      await controller.toggleTorch();
      _isTorchOnNotifier.value = !_isTorchOnNotifier.value;
    } catch (_) {
      // Ignored if hardware does not support torch or controller not initialized
    }
  }

  @override
  Future<void> start() async {
    try {
      await controller.start();
    } catch (_) {
      // Handled by MobileScanner on error
    }
  }

  @override
  Future<void> stop() async {
    try {
      await controller.stop();
    } catch (_) {
      // Ignored
    }
    if (_isTorchOnNotifier.value) {
      // Restore idle state: the camera stream is gone, so force the hardware
      // torch off before reconciling the notifier back to false.
      try {
        await controller.toggleTorch();
      } catch (_) {
        // Ignored if hardware does not support torch or controller not initialized
      }
      _isTorchOnNotifier.value = false;
    }
  }

  @override
  void dispose() {
    _isTorchOnNotifier.dispose();
    controller.dispose();
  }
}
