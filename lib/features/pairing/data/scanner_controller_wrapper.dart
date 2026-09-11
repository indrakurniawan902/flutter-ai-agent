import 'package:flutter/foundation.dart';
import 'package:flutter_ai_agent/features/pairing/domain/qr_scanner_controller.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Clean Architecture wrapper for [MobileScannerController].
class MobileScannerControllerWrapper implements QrScannerControllerBase {
  final MobileScannerController controller;
  final ValueNotifier<bool> _isTorchOnNotifier;

  MobileScannerControllerWrapper({MobileScannerController? controller})
      : controller = controller ??
            MobileScannerController(
              formats: const [BarcodeFormat.qrCode],
              detectionSpeed: DetectionSpeed.noDuplicates,
            ),
        _isTorchOnNotifier = ValueNotifier<bool>(false);

  @override
  ValueListenable<bool> get isTorchOn => _isTorchOnNotifier;

  @override
  Future<void> toggleTorch() async {
    try {
      await controller.toggleTorch();
    } catch (_) {
      // Ignored if hardware does not support torch or controller not initialized
    }
    _isTorchOnNotifier.value = !_isTorchOnNotifier.value;
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
  }

  @override
  void dispose() {
    _isTorchOnNotifier.dispose();
    controller.dispose();
  }
}
