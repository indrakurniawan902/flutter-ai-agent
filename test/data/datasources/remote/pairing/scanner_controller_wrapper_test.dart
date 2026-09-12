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
  });
}
