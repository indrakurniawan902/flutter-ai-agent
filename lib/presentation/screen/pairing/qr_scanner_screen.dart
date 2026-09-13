import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/pairing_parser.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/qr_scanner_controller.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// QR Code Scanner Screen for pairing with Hermes / OpenClaw gateway.
///
/// Features:
/// - Camera viewfinder overlay with target frame.
/// - Flashlight/torch toggle button.
/// - Manual input fallback dialog.
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

  const QrScannerScreen({
    super.key,
    this.controller,
    this.parser = const PairingParser(),
    this.currentTime,
    this.onPayloadScanned,
    this.scannerWidgetBuilder,
  });

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  QrScannerControllerBase? _controller;
  late final bool _isExternalController;
  bool _isProcessing = false;

  static const Color darkSurface = Color(0xFF0F172A);
  static const Color accentTeal = Color(0xFF008080);
  static const Color neutralBorder = Color(0xFF334155);

  @override
  void initState() {
    super.initState();
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
  }

  @override
  void dispose() {
    if (!_isExternalController) {
      _controller?.dispose();
    }
    super.dispose();
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
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ValueListenableBuilder<bool>(
                valueListenable: isTorchOnNotifier,
                builder: (context, isTorchOn, child) {
                  return IconButton(
                    key: const Key('qr_torch_toggle_button'),
                    tooltip: isTorchOn ? 'Turn Flashlight Off' : 'Turn Flashlight On',
                    icon: Icon(
                      isTorchOn ? Icons.flash_on : Icons.flash_off,
                      color: isTorchOn ? accentTeal : Colors.white,
                    ),
                    onPressed: () => _controller?.toggleTorch(),
                  );
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                key: const Key('qr_torch_toggle_button'),
                tooltip: 'Turn Flashlight On',
                icon: const Icon(
                  Icons.flash_off,
                  color: Colors.white,
                ),
                onPressed: () => _controller?.toggleTorch(),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          // Camera scanner layer
          Positioned.fill(
            child: widget.scannerWidgetBuilder != null
                ? widget.scannerWidgetBuilder!(context, _handleBarcode)
                : MobileScanner(
                    onDetect: (capture) {
                      for (final barcode in capture.barcodes) {
                        final raw = barcode.rawValue;
                        if (raw != null && raw.isNotEmpty) {
                          _handleBarcode(raw);
                          break;
                        }
                      }
                    },
                  ),
          ),

          // Viewfinder Overlay
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

/// Overlay with darkened outer boundary and transparent cutout for viewfinder.
class _ViewfinderOverlay extends StatelessWidget {
  const _ViewfinderOverlay();

  static const double boxSize = 250.0;

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
            // Scrim with punched-out cutout, border, and corner brackets.
            Positioned.fill(
              child: CustomPaint(
                painter: _ViewfinderPainter(
                  cutout: Rect.fromLTWH(left, top, boxSize, boxSize),
                ),
              ),
            ),

            // Instruction label
            Positioned(
              left: 20,
              right: 20,
              top: top + boxSize + 24,
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Paints the dark scrim (with cutout), teal frame border, and corner brackets.
class _ViewfinderPainter extends CustomPainter {
  const _ViewfinderPainter({required this.cutout});

  final Rect cutout;

  static const double _cornerRadius = 16.0;
  static const double _bracketLeg = 24.0;
  static const double _bracketStroke = 3.0;
  static const Color accentTeal = Color(0xFF008080);

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Path()..addRect(Offset.zero & size);
    final cutoutRRect =
        RRect.fromRectAndRadius(cutout, const Radius.circular(_cornerRadius));
    final scrim = Path.combine(
      PathOperation.difference,
      outer,
      Path()..addRRect(cutoutRRect),
    );
    canvas.drawPath(
      scrim,
      Paint()..color = Colors.black.withValues(alpha: 0.65),
    );

    canvas.drawRRect(
      cutoutRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0
        ..color = accentTeal,
    );

    final brackets = Path()
      // Top-left
      ..moveTo(cutout.left, cutout.top + _bracketLeg)
      ..lineTo(cutout.left, cutout.top + _cornerRadius)
      ..arcToPoint(
        Offset(cutout.left + _cornerRadius, cutout.top),
        radius: const Radius.circular(_cornerRadius),
      )
      ..lineTo(cutout.left + _bracketLeg, cutout.top)
      // Top-right
      ..moveTo(cutout.right - _bracketLeg, cutout.top)
      ..lineTo(cutout.right - _cornerRadius, cutout.top)
      ..arcToPoint(
        Offset(cutout.right, cutout.top + _cornerRadius),
        radius: const Radius.circular(_cornerRadius),
      )
      ..lineTo(cutout.right, cutout.top + _bracketLeg)
      // Bottom-right
      ..moveTo(cutout.right, cutout.bottom - _bracketLeg)
      ..lineTo(cutout.right, cutout.bottom - _cornerRadius)
      ..arcToPoint(
        Offset(cutout.right - _cornerRadius, cutout.bottom),
        radius: const Radius.circular(_cornerRadius),
      )
      ..lineTo(cutout.right - _bracketLeg, cutout.bottom)
      // Bottom-left
      ..moveTo(cutout.left + _bracketLeg, cutout.bottom)
      ..lineTo(cutout.left + _cornerRadius, cutout.bottom)
      ..arcToPoint(
        Offset(cutout.left, cutout.bottom - _cornerRadius),
        radius: const Radius.circular(_cornerRadius),
      )
      ..lineTo(cutout.left, cutout.bottom - _bracketLeg);
    canvas.drawPath(
      brackets,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = _bracketStroke
        ..strokeCap = StrokeCap.round
        ..color = accentTeal,
    );
  }

  @override
  bool shouldRepaint(covariant _ViewfinderPainter oldDelegate) =>
      oldDelegate.cutout != cutout;
}
