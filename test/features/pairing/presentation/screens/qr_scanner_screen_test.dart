import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_ai_agent/features/pairing/data/models/pairing_payload.dart';
import 'package:flutter_ai_agent/features/pairing/domain/pairing_parser.dart';
import 'package:flutter_ai_agent/features/pairing/presentation/screens/qr_scanner_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

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
    return MaterialApp(
      theme: AppTheme.darkTheme,
      navigatorObservers: [mockNavObserver],
      home: QrScannerScreen(
        controller: mockController,
        parser: const PairingParser(),
        currentTime: testNow,
        onPayloadScanned: onPayloadScanned,
        scannerWidgetBuilder: scannerWidgetBuilder,
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
}
