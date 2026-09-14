import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/domain/entities/chat/action_step.dart';

void main() {
  group('ActionStep & ActionStepStatus', () {
    test('ActionStepStatus getters reflect current state correctly', () {
      expect(ActionStepStatus.pending.isPending, isTrue);
      expect(ActionStepStatus.pending.isInProgress, isFalse);
      expect(ActionStepStatus.pending.isDone, isFalse);
      expect(ActionStepStatus.pending.isError, isFalse);

      expect(ActionStepStatus.inProgress.isInProgress, isTrue);
      expect(ActionStepStatus.inProgress.isPending, isFalse);

      expect(ActionStepStatus.done.isDone, isTrue);
      expect(ActionStepStatus.done.isPending, isFalse);

      expect(ActionStepStatus.error.isError, isTrue);
      expect(ActionStepStatus.error.isDone, isFalse);
    });

    test('ActionStep supports value equality and copyWith', () {
      const step1 = ActionStep(
        id: 'step_1',
        title: 'get_device_status',
        description: 'Checking battery and connectivity',
        status: ActionStepStatus.pending,
        parameters: {'battery': true},
      );

      const step2 = ActionStep(
        id: 'step_1',
        title: 'get_device_status',
        description: 'Checking battery and connectivity',
        status: ActionStepStatus.pending,
        parameters: {'battery': true},
      );

      expect(step1, equals(step2));

      final updated = step1.copyWith(
        status: ActionStepStatus.done,
        output: {'batteryLevel': 95, 'isCharging': true},
      );

      expect(updated.status, equals(ActionStepStatus.done));
      expect(updated.output, equals({'batteryLevel': 95, 'isCharging': true}));
      expect(updated.id, equals('step_1'));
      expect(updated.parameters, equals({'battery': true}));
      expect(updated, isNot(equals(step1)));
    });

    test('ActionStep handles error message and output formatting', () {
      const step = ActionStep(
        id: 'step_error',
        title: 'camera_take_photo',
        status: ActionStepStatus.error,
        errorMessage: 'User cancelled image capture',
      );

      expect(step.status.isError, isTrue);
      expect(step.errorMessage, equals('User cancelled image capture'));
    });
  });
}
