import 'package:flutter_ai_agent/data/datasources/remote/pairing/scanner_controller_wrapper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mocktail/mocktail.dart';

class MockMobileScannerController extends Mock implements MobileScannerController {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MobileScannerControllerWrapper', () {
    test('initializes with torch off by default', () {
      final mockController = MockMobileScannerController();
      when(() => mockController.dispose()).thenAnswer((_) async {});

      final wrapper = MobileScannerControllerWrapper(controller: mockController);

      expect(wrapper.isTorchOn.value, isFalse);
      expect(wrapper.controller, equals(mockController));

      wrapper.dispose();
    });

    test('toggleTorch toggles isTorchOn value on success', () async {
      final mockController = MockMobileScannerController();
      when(() => mockController.toggleTorch()).thenAnswer((_) async {});
      when(() => mockController.dispose()).thenAnswer((_) async {});

      final wrapper = MobileScannerControllerWrapper(controller: mockController);

      expect(wrapper.isTorchOn.value, isFalse);

      await wrapper.toggleTorch();
      expect(wrapper.isTorchOn.value, isTrue);
      verify(() => mockController.toggleTorch()).called(1);

      await wrapper.toggleTorch();
      expect(wrapper.isTorchOn.value, isFalse);
      verify(() => mockController.toggleTorch()).called(1);

      wrapper.dispose();
    });

    test('toggleTorch does not update isTorchOn when hardware toggle throws', () async {
      final mockController = MockMobileScannerController();
      when(() => mockController.toggleTorch()).thenThrow(Exception('Hardware error'));
      when(() => mockController.dispose()).thenAnswer((_) async {});

      final wrapper = MobileScannerControllerWrapper(controller: mockController);

      expect(wrapper.isTorchOn.value, isFalse);

      await wrapper.toggleTorch();
      // Should remain false because toggle failed
      expect(wrapper.isTorchOn.value, isFalse);

      wrapper.dispose();
    });

    test('scannerController returns the injected controller instance', () {
      final mockController = MockMobileScannerController();
      when(() => mockController.dispose()).thenAnswer((_) async {});

      final wrapper = MobileScannerControllerWrapper(controller: mockController);

      expect(wrapper.scannerController, same(mockController));

      wrapper.dispose();
    });

    test('start delegates to the inner controller', () async {
      final mockController = MockMobileScannerController();
      when(() => mockController.start()).thenAnswer((_) async {});
      when(() => mockController.dispose()).thenAnswer((_) async {});

      final wrapper = MobileScannerControllerWrapper(controller: mockController);

      await wrapper.start();

      verify(() => mockController.start()).called(1);

      wrapper.dispose();
    });

    test('stop resets torch state and forces the hardware torch off when it was on', () async {
      final mockController = MockMobileScannerController();
      when(() => mockController.toggleTorch()).thenAnswer((_) async {});
      when(() => mockController.stop()).thenAnswer((_) async {});
      when(() => mockController.dispose()).thenAnswer((_) async {});

      final wrapper = MobileScannerControllerWrapper(controller: mockController);

      await wrapper.toggleTorch();
      expect(wrapper.isTorchOn.value, isTrue);
      clearInteractions(mockController);

      await wrapper.stop();

      verify(() => mockController.stop()).called(1);
      verify(() => mockController.toggleTorch()).called(1);
      expect(wrapper.isTorchOn.value, isFalse);

      wrapper.dispose();
    });

    test('stop when torch already off does not touch the torch and stops once', () async {
      final mockController = MockMobileScannerController();
      when(() => mockController.toggleTorch()).thenAnswer((_) async {});
      when(() => mockController.stop()).thenAnswer((_) async {});
      when(() => mockController.dispose()).thenAnswer((_) async {});

      final wrapper = MobileScannerControllerWrapper(controller: mockController);

      expect(wrapper.isTorchOn.value, isFalse);

      await wrapper.stop();

      verify(() => mockController.stop()).called(1);
      verifyNever(() => mockController.toggleTorch());
      expect(wrapper.isTorchOn.value, isFalse);

      wrapper.dispose();
    });

    test('stop swallows exceptions thrown by the inner controller', () async {
      final mockController = MockMobileScannerController();
      when(() => mockController.stop()).thenThrow(Exception('Camera error'));
      when(() => mockController.dispose()).thenAnswer((_) async {});

      final wrapper = MobileScannerControllerWrapper(controller: mockController);

      await expectLater(wrapper.stop(), completes);
      expect(wrapper.isTorchOn.value, isFalse);

      wrapper.dispose();
    });

    test('stop resets torch state even when the forced torch toggle throws', () async {
      final mockController = MockMobileScannerController();
      when(() => mockController.toggleTorch()).thenAnswer((_) async {});
      when(() => mockController.stop()).thenAnswer((_) async {});
      when(() => mockController.dispose()).thenAnswer((_) async {});

      final wrapper = MobileScannerControllerWrapper(controller: mockController);

      await wrapper.toggleTorch();
      expect(wrapper.isTorchOn.value, isTrue);

      when(() => mockController.toggleTorch()).thenThrow(Exception('Hardware error'));

      await expectLater(wrapper.stop(), completes);
      expect(wrapper.isTorchOn.value, isFalse);

      wrapper.dispose();
    });
  });
}
