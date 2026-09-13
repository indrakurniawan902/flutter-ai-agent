import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/remote/pairing/scanner_controller_wrapper.dart';
import 'package:flutter_ai_agent/domain/tools/pairing/qr_scanner_controller.dart';
import 'package:flutter_ai_agent/presentation/screen/pairing/qr_scanner_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

class MockMobileScannerController extends Mock implements MobileScannerController {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockMobileScannerController mockInner;
  late MobileScannerControllerWrapper wrapper;
  late MobileScannerController initialValueCarrier;

  setUp(() async {
    // GetIt.reset() is asynchronous: awaiting it prevents its deferred cleanup
    // from wiping test registrations on subsequent pumps.
    await getIt.reset();

    mockInner = MockMobileScannerController();
    wrapper = MobileScannerControllerWrapper(controller: mockInner);
    initialValueCarrier = MobileScannerController();

    when(() => mockInner.autoStart).thenReturn(true);
    when(() => mockInner.start()).thenAnswer((_) async {});
    when(() => mockInner.stop()).thenAnswer((_) async {});
    when(() => mockInner.toggleTorch()).thenAnswer((_) async {});
    when(() => mockInner.updateScanWindow(any())).thenAnswer((_) async {});
    when(() => mockInner.barcodes).thenAnswer((_) => const Stream<BarcodeCapture>.empty());
    when(() => mockInner.dispose()).thenAnswer((_) async {});
    when(() => mockInner.value).thenReturn(initialValueCarrier.value);

    getIt.registerLazySingleton<QrScannerControllerBase>(() => wrapper);
  });

  tearDown(() async {
    initialValueCarrier.dispose();
    await getIt.reset();
  });

  Widget buildScreen({QrScannerControllerBase? controller}) {
    return MaterialApp(
      home: QrScannerScreen(controller: controller, currentTime: DateTime(2026, 9, 11)),
    );
  }

  group('QrScannerScreen lifecycle - DI provided singleton', () {
    testWidgets('exposes the wrapper inner controller as the attached native controller',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();

      expect(identical(wrapper.scannerController, wrapper.controller), isTrue);
      expect(wrapper.scannerController, same(mockInner));

      final mobileScanner = tester.widget<MobileScanner>(find.byType(MobileScanner));
      expect(mobileScanner.controller, same(mockInner));

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('torch toggle updates the wrapper notifier and unmount stops + resets torch',
        (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();

      expect(wrapper.isTorchOn.value, isFalse);

      await tester.tap(find.byKey(const Key('qr_torch_toggle_button')));
      await tester.pump();
      expect(wrapper.isTorchOn.value, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      verify(() => mockInner.stop()).called(greaterThanOrEqualTo(1));
      expect(wrapper.isTorchOn.value, isFalse);
    });

    testWidgets('remount restarts cleanly with torch state reset', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();

      await tester.tap(find.byKey(const Key('qr_torch_toggle_button')));
      await tester.pump();
      expect(wrapper.isTorchOn.value, isTrue);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      expect(wrapper.isTorchOn.value, isFalse);

      // Re-entering the screen must not throw and must start from torch off.
      // start() is driven by MobileScanner internals, so assert the screen
      // re-initialised cleanly instead of verifying a start() call.
      await tester.pumpWidget(buildScreen());
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('qr_torch_toggle_button')), findsOneWidget);
      expect(wrapper.isTorchOn.value, isFalse);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    });

    testWidgets('never disposes the app-owned singleton on unmount', (tester) async {
      await tester.pumpWidget(buildScreen());
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      verifyNever(() => mockInner.dispose());
    });
  });

  group('QrScannerScreen lifecycle - externally supplied controller', () {
    testWidgets('unmounting does not stop the external controller', (tester) async {
      final external = MockQrScannerController();
      when(() => external.isTorchOn).thenReturn(ValueNotifier<bool>(false));
      when(() => external.toggleTorch()).thenAnswer((_) async {});
      when(() => external.start()).thenAnswer((_) async {});
      when(() => external.stop()).thenAnswer((_) async {});
      when(() => external.dispose()).thenAnswer((_) {});

      await tester.pumpWidget(buildScreen(controller: external));
      await tester.pump();

      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      verifyNever(() => external.stop());
      verifyNever(() => external.dispose());
    });
  });
}
