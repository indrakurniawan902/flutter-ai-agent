import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/features/chat/domain/models/generative_card_data.dart';

void main() {
  group('GenerativeCardData Models', () {
    test('ActionConfirmationData supports value equality and copyWith', () {
      const data1 = ActionConfirmationData(
        title: 'Execute Location Check',
        message: 'Agent requests permission to access GPS coordinates.',
        parameters: {'accuracy': 'high'},
        primaryActionLabel: 'Authorize',
        secondaryActionLabel: 'Deny',
        tierLabel: 'Tier 2 Permission',
      );

      const data2 = ActionConfirmationData(
        title: 'Execute Location Check',
        message: 'Agent requests permission to access GPS coordinates.',
        parameters: {'accuracy': 'high'},
        primaryActionLabel: 'Authorize',
        secondaryActionLabel: 'Deny',
        tierLabel: 'Tier 2 Permission',
      );

      expect(data1, equals(data2));

      final copy = data1.copyWith(
        primaryActionLabel: 'Allow Once',
        isConfirmed: true,
      );

      expect(copy.primaryActionLabel, equals('Allow Once'));
      expect(copy.isConfirmed, isTrue);
      expect(copy.isDismissed, isFalse);
    });

    test('SummaryCardData supports items and serialization', () {
      const item1 = SummaryMetricItem(label: 'Total Tools', value: '4');
      const item2 = SummaryMetricItem(label: 'Execution Time', value: '1.2s');

      const summary = SummaryCardData(
        title: 'Workflow Execution Report',
        summaryText: 'All requested actions completed successfully.',
        items: [item1, item2],
        metadata: {'status': 'success'},
      );

      expect(summary.items.length, equals(2));
      expect(summary.items.first.label, equals('Total Tools'));
      expect(summary.items.first.value, equals('4'));
      expect(summary.title, equals('Workflow Execution Report'));
    });
  });
}
