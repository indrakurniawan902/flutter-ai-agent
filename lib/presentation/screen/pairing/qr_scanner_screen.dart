import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/pairing_parser.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/qr_scanner_controller.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/app_settings_opener.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/permission_rationale_modal.dart';
import 'package:flutter_ai_agent/utils/permission_gate.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

/// QR Code Scanner Screen for pairing with Hermes / OpenClaw gateway.
///
/// Features:
/// - Camera viewfinder overlay with target frame.
/// - Flashlight/torch toggle button.
/// - Manual input fallback dialog.
/// - PermissionGate integration (denied, permanently denied, camera-busy friendly states).
/// - Clean Architecture separation using [QrScannerControllerBase] and [PairingParser].
class QrScannerScreen extends StatefulWidget {
  final QrScannerControllerBase? controller;
  final PairingParser parser;
  final DateTime? currentTime;
  final void Function(PairingPayload payload)? onPayloadScanned;
  final Widget Function(
    BuildContext context,
    void Function(String barcode) onDetect,
  )? scannerWidgetBuilder;
  final PermissionGate? permissionGate;

  const QrScannerScreen({
    super.key,
    this.controller,
    this.parser = const PairingParser(),
    this.currentTime,
    this.onPayloadScanned,
    this.scannerWidgetBuilder,
    this.permissionGate,
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen>
    with WidgetsBindingObserver {
  QrScannerControllerBase? _controller;
  late final bool _isExternalController;
  late final PermissionGate _permissionGate;
  PermissionStatus? _cameraStatus;
  bool _hasCameraError = false;
  int _scannerEpoch = 0;
  bool _isProcessing = false;

  static const Color darkSurface = Color(0xFF0F172A);
  static const Color surfaceContainer = Color(0xFF1E293B);
  static const Color accentTeal = Color(0xFF008080);
  static const Color neutralBorder = Color(0xFF334155);
  static const Color inkSecondary = Color(0xFF94A3B8);

  bool get _isCameraGranted => _cameraStatus?.isGranted == true;

  bool get _permissionGateCanRun =>
      widget.permissionGate != null ||
      getIt.isRegistered<PermissionGate>() ||
      !Platform.environment.containsKey('FLUTTER_TEST');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.controller != null) {
      _controller = widget.controller;
      _isExternalController = true;
    } else if (getIt.isRegistered<QrScannerControllerBase>()) {
      _controller = getIt<QrScannerControllerBase>();
      _isExternalController = true;
    } else {
      _controller = null;
      _isExternalController = false;
    }

    final injectedGate = widget.permissionGate ??
        (getIt.isRegistered<PermissionGate>() ? getIt<PermissionGate>() : null);

    if (injectedGate != null) {
      _permissionGate = injectedGate;
      _cameraStatus = null;
      _checkCameraPermission();
    } else if (Platform.environment.containsKey('FLUTTER_TEST')) {
      _permissionGate = PermissionGate();
      _cameraStatus = PermissionStatus.granted;
    } else {
      _permissionGate = PermissionGate();
      _cameraStatus = null;
      _checkCameraPermission();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (!_isExternalController) {
      _controller?.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _permissionGateCanRun) {
      _checkCameraPermission();
    }
  }

  Future<void> _checkCameraPermission() async {
    if (!_permissionGateCanRun) return;
    final status = await _permissionGate.check(PermissionRationaleType.camera);
    if (!mounted) return;
    setState(() {
      _cameraStatus = status;
      if (!status.isGranted) {
        _hasCameraError = false;
      }
    });
  }

  void _handleBarcode(String rawBarcode) {
    if (_isProcessing) return;
    _isProcessing = true;

    final result = widget.parser.parse(
      rawBarcode,
      currentTime: widget.currentTime,
    );

    result.fold(
      (failure) {
        _isProcessing = false;
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(failure.message),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
          ),
        );
      },
      (payload) {
        if (!mounted) return;
        widget.onPayloadScanned?.call(payload);
        Navigator.of(context).pop(payload);
      },
    );
  }

  Future<void> _showManualInputDialog() async {
    final textController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          key: const Key('manual_input_dialog'),
          backgroundColor: darkSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: neutralBorder),
          ),
          title: const Text(
            'Manual Pairing Input',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Paste JSON pairing payload from terminal:',
                style: TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('manual_input_textfield'),
                controller: textController,
                maxLines: 5,
                style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
                decoration: InputDecoration(
                  hintText: '{\n  "gatewayUrl": "...",\n  "token": "..."\n}',
                  hintStyle: const TextStyle(color: Color(0xFF64748B)),
                  filled: true,
                  fillColor: const Color(0xFF1E293B),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: neutralBorder),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: accentTeal),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              key: const Key('manual_input_cancel_button'),
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF94A3B8)),
              ),
            ),
            ElevatedButton(
              key: const Key('manual_input_submit_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              onPressed: () {
                final text = textController.text;
                Navigator.of(dialogContext).pop();
                _handleBarcode(text);
              },
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLoadingPlaceholder() {
    return const Center(
      key: Key('qr_camera_loading_placeholder'),
      child: CircularProgressIndicator(
        color: accentTeal,
      ),
    );
  }

  Widget _buildPermissionDeniedState({required bool isPermanentlyDenied}) {
    return Center(
      key: const Key('qr_camera_permission_denied_view'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(
          left: 32.0,
          right: 32.0,
          top: 16.0,
          bottom: 110.0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: neutralBorder),
              ),
              child: const Icon(
                Icons.camera_alt_rounded,
                size: 32,
                color: accentTeal,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Akses Kamera Diperlukan',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Akses kamera diperlukan untuk memindai QR pairing',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: inkSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            if (isPermanentlyDenied) ...[
              const SizedBox(height: 12),
              const Text(
                'Izin ini ditolak permanen. Aktifkan manual dari pengaturan aplikasi di sistem.',
                key: Key('permission_rationale_permanently_denied_notice'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: inkSecondary,
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                key: const Key('qr_camera_open_settings_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: () async {
                  final opener = _permissionGate.settingsOpener ??
                      AppSettingsOpenerRegistry.instance;
                  try {
                    await opener.openAppSettings();
                  } catch (_) {}
                },
                child: const Text(
                  'Buka Pengaturan',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ] else ...[
              const SizedBox(height: 20),
              ElevatedButton(
                key: const Key('qr_camera_grant_button'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentTeal,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                onPressed: () async {
                  await _permissionGate.requestWithRationale(
                    context,
                    PermissionRationaleType.camera,
                  );
                  await _checkCameraPermission();
                },
                child: const Text(
                  'Izinkan',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCameraBusyState() {
    return CameraBusyView(
      onRetry: () {
        setState(() {
          _hasCameraError = false;
          _scannerEpoch++;
        });
        _controller?.start();
      },
    );
  }

  Widget _buildBodyContent() {
    if (_cameraStatus == null) {
      return _buildLoadingPlaceholder();
    }

    if (_cameraStatus!.isPermanentlyDenied || _cameraStatus!.isRestricted) {
      return _buildPermissionDeniedState(isPermanentlyDenied: true);
    }

    if (!_cameraStatus!.isGranted) {
      return _buildPermissionDeniedState(isPermanentlyDenied: false);
    }

    if (_hasCameraError) {
      return _buildCameraBusyState();
    }

    return widget.scannerWidgetBuilder != null
        ? widget.scannerWidgetBuilder!(context, _handleBarcode)
        : MobileScanner(
            key: ValueKey(_scannerEpoch),
            errorBuilder: (context, error, child) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_hasCameraError) {
                  setState(() {
                    _hasCameraError = true;
                  });
                }
              });
              return _buildCameraBusyState();
            },
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final raw = barcode.rawValue;
                if (raw != null && raw.isNotEmpty) {
                  _handleBarcode(raw);
                  break;
                }
              }
            },
          );
  }

  @override
  Widget build(BuildContext context) {
    final isTorchOnNotifier = _controller?.isTorchOn;

    return Scaffold(
      backgroundColor: darkSurface,
      appBar: AppBar(
        title: const Text('Scan Pairing Code'),
        backgroundColor: darkSurface,
        elevation: 0,
        actions: [
          if (isTorchOnNotifier != null)
            ValueListenableBuilder<bool>(
              valueListenable: isTorchOnNotifier,
              builder: (context, isTorchOn, child) {
                return IconButton(
                  key: const Key('qr_torch_toggle_button'),
                  tooltip:
                      isTorchOn ? 'Turn Flashlight Off' : 'Turn Flashlight On',
                  icon: Icon(
                    isTorchOn ? Icons.flash_on : Icons.flash_off,
                    color: isTorchOn ? accentTeal : Colors.white,
                  ),
                  onPressed: () => _controller?.toggleTorch(),
                );
              },
            )
          else
            IconButton(
              key: const Key('qr_torch_toggle_button'),
              tooltip: 'Turn Flashlight On',
              icon: const Icon(
                Icons.flash_off,
                color: Colors.white,
              ),
              onPressed: () => _controller?.toggleTorch(),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Main content layer based on _cameraStatus
          Positioned.fill(
            child: _buildBodyContent(),
          ),

          // Viewfinder Overlay (only when camera is granted and no error)
          if (_isCameraGranted && !_hasCameraError)
            Positioned.fill(
              key: const Key('qr_viewfinder_overlay'),
              child: const _ViewfinderOverlay(),
            ),

          // Manual Input Fallback Bar at the bottom
          Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: SafeArea(
              child: OutlinedButton.icon(
                key: const Key('qr_manual_input_button'),
                style: OutlinedButton.styleFrom(
                  backgroundColor: darkSurface.withValues(alpha: 0.85),
                  side: const BorderSide(color: accentTeal),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: const Icon(Icons.edit_note, color: accentTeal),
                label: const Text(
                  'Enter Code Manually',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onPressed: _showManualInputDialog,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Friendly camera busy state widget.
class CameraBusyView extends StatelessWidget {
  final VoidCallback onRetry;

  const CameraBusyView({
    super.key,
    required this.onRetry,
  });

  static const Color surfaceContainer = Color(0xFF1E293B);
  static const Color neutralBorder = Color(0xFF334155);
  static const Color accentTeal = Color(0xFF008080);
  static const Color inkSecondary = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    return Center(
      key: const Key('qr_camera_busy_view'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(
          left: 32.0,
          right: 32.0,
          top: 16.0,
          bottom: 110.0,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: surfaceContainer,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: neutralBorder),
              ),
              child: const Icon(
                Icons.videocam_off_rounded,
                size: 32,
                color: accentTeal,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Kamera Tidak Tersedia',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Kamera sedang dipakai aplikasi lain',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: inkSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              key: const Key('qr_camera_retry_button'),
              style: ElevatedButton.styleFrom(
                backgroundColor: accentTeal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
              onPressed: onRetry,
              child: const Text(
                'Coba Lagi',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Overlay with darkened outer boundary and transparent cutout for viewfinder.
class _ViewfinderOverlay extends StatelessWidget {
  const _ViewfinderOverlay();

  static const double boxSize = 250.0;
  static const Color accentTeal = Color(0xFF008080);

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;
        final left = (screenWidth - boxSize) / 2;
        final top = (screenHeight - boxSize) / 2 - 40;

        return Stack(
          children: [
            // Darkened backdrop around cutout
            ColorFiltered(
              colorFilter: ColorFilter.mode(
                Colors.black.withValues(alpha: 0.65),
                BlendMode.srcOut,
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      backgroundBlendMode: BlendMode.dstOut,
                    ),
                  ),
                  Positioned(
                    left: left,
                    top: top,
                    width: boxSize,
                    height: boxSize,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Viewfinder Border and Corner Accents
            Positioned(
              left: left,
              top: top,
              width: boxSize,
              height: boxSize,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accentTeal, width: 2.0),
                ),
              ),
            ),

            // Instruction label
            Positioned(
              left: 20,
              right: 20,
              top: top + boxSize + 24,
              child: const Text(
                'Align QR code within the frame',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
