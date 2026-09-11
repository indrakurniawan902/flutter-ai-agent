import 'package:flutter_ai_agent/features/pairing/data/scanner_controller_wrapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MobileScannerControllerWrapper', () {
    test('initializes with torch off by default', () {
      final wrapper = MobileScannerControllerWrapper();

      expect(wrapper.isTorchOn.value, isFalse);
      expect(wrapper.controller, isNotNull);

      wrapper.dispose();
    });

    test('toggleTorch toggles isTorchOn value', () async {
      final wrapper = MobileScannerControllerWrapper();

      expect(wrapper.isTorchOn.value, isFalse);

      await wrapper.toggleTorch();
      expect(wrapper.isTorchOn.value, isTrue);

      await wrapper.toggleTorch();
      expect(wrapper.isTorchOn.value, isFalse);

      wrapper.dispose();
    });
  });
}
