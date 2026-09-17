import 'package:flutter_ai_agent/domain/tools/chat/accessibility_inspector_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('accessibility recovery state', () {
    const nonActive = <AccessibilityStatus>[
      AccessibilityStatus.notEnabled,
      AccessibilityStatus.denied,
      AccessibilityStatus.grantedNotConnected,
    ];

    test('active returns the empty string', () {
      expect(AccessibilityMessages.forStatus(AccessibilityStatus.active), '');
    });

    test(
        'each non-active state is a distinct, recoverable accessibility failure '
        'that never classifies as a generic permission denial', () {
      for (final status in nonActive) {
        final message = AccessibilityMessages.forStatus(status);

        expect(message, isNotEmpty);
        expect(message, startsWith('[accessibility_'));
        expect(
          message,
          contains('launch_system_setting(setting_type="accessibility")'),
        );
        expect(message, isNot(contains('Permission not granted')));
        expect(message, isNot(contains('permission was denied')));
      }
    });
  });
}
