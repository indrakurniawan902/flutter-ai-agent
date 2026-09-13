import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/pairing_parser.dart';
import 'package:flutter_ai_agent/presentation/screen/pairing/qr_scanner_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

class MockNavigatorObserver extends Mock implements NavigatorObserver {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockQrScannerController mockController;
  late ValueNotifier<bool> torchNotifier;
  late MockNavigatorObserver mockNavObserver;
  final testNow = DateTime.parse('2026-09-11T08:10:00.000Z');

  setUpAll(() {
    registerFallbackValue(
      MaterialPageRoute<dynamic>(builder: (_) => const SizedBox()),
    );
  });

  setUp(() {
    mockController = MockQrScannerController();
    torchNotifier = ValueNotifier<bool>(false);
    mockNavObserver = MockNavigatorObserver();

    when(() => mockController.isTorchOn).thenReturn(torchNotifier);
    when(() => mockController.toggleTorch()).thenAnswer((_) async {
      torchNotifier.value = !torchNotifier.value;
    });
    when(() => mockController.start()).thenAnswer((_) async {});
    when(() => mockController.stop()).thenAnswer((_) async {});
    when(() => mockController.dispose()).thenReturn(null);
  });

  tearDown(() {
    torchNotifier.dispose();
  });

  Widget buildTestWidget({
    void Function(PairingPayload)? onPayloadScanned,
    Widget Function(BuildContext, void Function(String))? scannerWidgetBuilder,
  }) {
    return RepaintBoundary(
      child: MaterialApp(
        theme: AppTheme.darkTheme,
        navigatorObservers: [mockNavObserver],
        home: QrScannerScreen(
          controller: mockController,
          parser: const PairingParser(),
          currentTime: testNow,
          onPayloadScanned: onPayloadScanned,
          scannerWidgetBuilder: scannerWidgetBuilder,
        ),
      ),
    );
  }

  group('QrScannerScreen - UI & Elements', () {
    testWidgets('renders dark theme styling, viewfinder, torch button, and manual input button',
        (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          scannerWidgetBuilder: (context, onDetect) => const SizedBox(key: Key('mock_camera_preview')),
        ),
      );
      await tester.pump();

      expect(find.text('Scan Pairing Code'), findsOneWidget);
      expect(find.byKey(const Key('qr_torch_toggle_button')), findsOneWidget);
      expect(find.byKey(const Key('qr_viewfinder_overlay')), findsOneWidget);
      expect(find.byKey(const Key('qr_manual_input_button')), findsOneWidget);
      expect(find.text('Align QR code within the frame'), findsOneWidget);
      expect(find.byIcon(Icons.flash_off), findsOneWidget);
    });

    testWidgets('tapping torch toggle button calls toggleTorch and updates icon',
        (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          scannerWidgetBuilder: (context, onDetect) => const SizedBox(),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.flash_off), findsOneWidget);

      await tester.tap(find.byKey(const Key('qr_torch_toggle_button')));
      await tester.pump();

      verify(() => mockController.toggleTorch()).called(1);
      expect(find.byIcon(Icons.flash_on), findsOneWidget);
    });
  });

  group('QrScannerScreen - Scanning Functionality (Positive & Negative)', () {
    testWidgets('positive: valid JSON pairing payload parsed and pops navigator',
        (tester) async {
      PairingPayload? scannedPayload;
      void Function(String)? triggerScan;

      await tester.pumpWidget(
        buildTestWidget(
          onPayloadScanned: (payload) {
            scannedPayload = payload;
          },
          scannerWidgetBuilder: (context, onDetect) {
            triggerScan = onDetect;
            return const SizedBox();
          },
        ),
      );
      await tester.pump();

      final validJson = jsonEncode({
        'gatewayUrl': 'https://vps.example.com:18789',
        'token': 'secret-token-abc',
        'profileName': 'VPS Oracle',
        'timestamp': '2026-09-11T08:05:00.000Z',
      });

      triggerScan!(validJson);
      await tester.pumpAndSettle();

      expect(scannedPayload, isNotNull);
      expect(scannedPayload?.gatewayUrl, 'https://vps.example.com:18789');
      expect(scannedPayload?.token, 'secret-token-abc');
      expect(scannedPayload?.profileName, 'VPS Oracle');
    });

    testWidgets('negative: malformed JSON shows SnackBar error', (tester) async {
      PairingPayload? scannedPayload;
      void Function(String)? triggerScan;

      await tester.pumpWidget(
        buildTestWidget(
          onPayloadScanned: (payload) => scannedPayload = payload,
          scannerWidgetBuilder: (context, onDetect) {
            triggerScan = onDetect;
            return const SizedBox();
          },
        ),
      );
      await tester.pump();

      triggerScan!('not_valid_json{{');
      await tester.pumpAndSettle();

      expect(scannedPayload, isNull);
      expect(find.textContaining('Malformed JSON'), findsOneWidget);
    });

    testWidgets('negative: invalid QR payload shows SnackBar error', (tester) async {
      PairingPayload? scannedPayload;
      void Function(String)? triggerScan;

      await tester.pumpWidget(
        buildTestWidget(
          onPayloadScanned: (payload) => scannedPayload = payload,
          scannerWidgetBuilder: (context, onDetect) {
            triggerScan = onDetect;
            return const SizedBox();
          },
        ),
      );
      await tester.pump();

      final invalidPayload = jsonEncode({
        'token': 'token-only',
        'timestamp': '2026-09-11T08:05:00.000Z',
      });

      triggerScan!(invalidPayload);
      await tester.pumpAndSettle();

      expect(scannedPayload, isNull);
      expect(find.textContaining('gatewayUrl is required'), findsOneWidget);
    });

    testWidgets('negative: expired token shows SnackBar error', (tester) async {
      PairingPayload? scannedPayload;
      void Function(String)? triggerScan;

      await tester.pumpWidget(
        buildTestWidget(
          onPayloadScanned: (payload) => scannedPayload = payload,
          scannerWidgetBuilder: (context, onDetect) {
            triggerScan = onDetect;
            return const SizedBox();
          },
        ),
      );
      await tester.pump();

      final expiredPayload = jsonEncode({
        'gatewayUrl': 'https://vps.example.com:18789',
        'token': 'secret-token-abc',
        'profileName': 'VPS Oracle',
        'timestamp': '2026-09-11T07:40:00.000Z', // 30 mins ago (> 15 min maxAge)
      });

      triggerScan!(expiredPayload);
      await tester.pumpAndSettle();

      expect(scannedPayload, isNull);
      expect(find.textContaining('expired'), findsOneWidget);
    });
  });

  group('QrScannerScreen - Manual Input Fallback', () {
    testWidgets('manual input dialog opens and parses valid payload', (tester) async {
      PairingPayload? scannedPayload;

      await tester.pumpWidget(
        buildTestWidget(
          onPayloadScanned: (payload) => scannedPayload = payload,
          scannerWidgetBuilder: (context, onDetect) => const SizedBox(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('qr_manual_input_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('manual_input_dialog')), findsOneWidget);
      expect(find.byKey(const Key('manual_input_textfield')), findsOneWidget);

      final validJson = jsonEncode({
        'gatewayUrl': 'https://manual.example.com',
        'token': 'manual-tok',
        'profileName': 'Manual Profile',
        'timestamp': '2026-09-11T08:08:00.000Z',
      });

      await tester.enterText(find.byKey(const Key('manual_input_textfield')), validJson);
      await tester.tap(find.byKey(const Key('manual_input_submit_button')));
      await tester.pumpAndSettle();

      expect(scannedPayload, isNotNull);
      expect(scannedPayload?.gatewayUrl, 'https://manual.example.com');
      expect(scannedPayload?.token, 'manual-tok');
      expect(scannedPayload?.profileName, 'Manual Profile');
    });

    testWidgets('manual input dialog shows error when invalid', (tester) async {
      PairingPayload? scannedPayload;

      await tester.pumpWidget(
        buildTestWidget(
          onPayloadScanned: (payload) => scannedPayload = payload,
          scannerWidgetBuilder: (context, onDetect) => const SizedBox(),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const Key('qr_manual_input_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('manual_input_textfield')), 'bad payload');
      await tester.tap(find.byKey(const Key('manual_input_submit_button')));
      await tester.pumpAndSettle();

      expect(scannedPayload, isNull);
      expect(find.textContaining('Malformed JSON'), findsOneWidget);
    });
  });

  group('QrScannerScreen - Viewfinder Overlay Painting', () {
    Future<({ByteData bytes, int width, int height})> captureScreenBytes(
      WidgetTester tester,
    ) async {
      final RenderRepaintBoundary boundary =
          tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      late ByteData bytes;
      late int width;
      late int height;
      await tester.binding.runAsync(() async {
        final ui.Image image = await boundary.toImage(pixelRatio: 1.0);
        bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
        width = image.width;
        height = image.height;
        image.dispose();
      });
      return (bytes: bytes, width: width, height: height);
    }

    int pixelAt(ByteData bytes, int imageWidth, double x, double y) {
      final offset =
          ((y.round() * imageWidth) + x.round()) * 4; // RGBA byte order
      final r = bytes.getUint8(offset);
      final g = bytes.getUint8(offset + 1);
      final b = bytes.getUint8(offset + 2);
      final a = bytes.getUint8(offset + 3);
      return (a << 24) | (r << 16) | (g << 8) | b;
    }

    int redAt(ByteData bytes, int imageWidth, double x, double y) {
      final offset = ((y.round() * imageWidth) + x.round()) * 4;
      return bytes.getUint8(offset);
    }

    Rect overlayCutout(WidgetTester tester) {
      final overlayRect =
          tester.getRect(find.byKey(const Key('qr_viewfinder_overlay')));
      final cutoutTop = overlayRect.top + (overlayRect.height - 250) / 2 - 40;
      return Rect.fromLTWH(
        overlayRect.left + (overlayRect.width - 250) / 2,
        cutoutTop,
        250,
        250,
      );
    }

    testWidgets('cutout center is fully opaque camera feed (no scrim tint)',
        (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          scannerWidgetBuilder: (context, onDetect) =>
              const ColoredBox(color: Color(0xFFFF0000)),
        ),
      );
      await tester.pump();

      final cutout = overlayCutout(tester);
      final captured = await captureScreenBytes(tester);
      final centerPixel = pixelAt(
        captured.bytes,
        captured.width,
        cutout.center.dx,
        cutout.center.dy,
      );

      expect(centerPixel, 0xFFFF0000);
    });

    testWidgets('scrim darkens pixels outside the cutout frame',
        (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          scannerWidgetBuilder: (context, onDetect) =>
              const ColoredBox(color: Color(0xFFFF0000)),
        ),
      );
      await tester.pump();

      final overlayRect =
          tester.getRect(find.byKey(const Key('qr_viewfinder_overlay')));
      final captured = await captureScreenBytes(tester);
      final redChannel = redAt(
        captured.bytes,
        captured.width,
        overlayRect.left + 15,
        overlayRect.top + 15,
      );

      expect(redChannel, lessThan(150));
      expect(redChannel, greaterThan(0));
    });

    testWidgets('overlay contains CustomPaint scrim painter', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          scannerWidgetBuilder: (context, onDetect) => const SizedBox(),
        ),
      );
      await tester.pump();

      final customPaints = tester.widgetList<CustomPaint>(
        find.descendant(
          of: find.byKey(const Key('qr_viewfinder_overlay')),
          matching: find.byType(CustomPaint),
        ),
      );

      expect(customPaints, isNotEmpty);
      expect(
        customPaints
            .any((paint) => paint.painter?.runtimeType.toString() ==
                '_ViewfinderPainter'),
        isTrue,
      );
    });
  });
}
