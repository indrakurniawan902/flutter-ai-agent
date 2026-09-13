import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';
import 'package:flutter_ai_agent/domain/repositories/action_center/action_center_repository.dart';
import 'package:flutter_ai_agent/presentation/screen/action_center/action_center_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/action_center/cubit/action_center_cubit.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeActionCenterRepository extends Fake implements ActionCenterRepository {
  final List<ActionItem> items;
  int dismissCalls = 0;
  int markAsReadCalls = 0;

  FakeActionCenterRepository(this.items);

  @override
  Future<Either<Failure, List<ActionItem>>> getItems() async {
    final sorted = [...items]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return Right(sorted);
  }

  @override
  Future<Either<Failure, void>> markAsRead(String id) async {
    markAsReadCalls++;
    final index = items.indexWhere((e) => e.id == id);
    if (index != -1) {
      items[index] = items[index].copyWith(isRead: true);
    }
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> dismiss(String id) async {
    dismissCalls++;
    items.removeWhere((e) => e.id == id);
    return const Right(null);
  }
}

void main() {
  final now = DateTime.utc(2026, 1, 1, 12);

  ActionItem buildItem({
    String id = 'a1',
    String title = 'Battery low',
    String summary = 'Device dropped below 20 percent',
    Map<String, dynamic>? payload,
  }) {
    return ActionItem(
      id: id,
      title: title,
      summary: summary,
      timestamp: now.subtract(const Duration(minutes: 5)),
      source: 'battery_watchdog',
      actionPayload: payload,
    );
  }

  Widget wrap(Widget child) => MaterialApp(
        theme: HermesTheme.darkTheme,
        home: child,
      );

  group('ActionCenterScreen', () {
    testWidgets('renders item titles', (tester) async {
      final repo = FakeActionCenterRepository([
        buildItem(id: 'a1', title: 'Battery low'),
        buildItem(id: 'a2', title: 'Entered geofence'),
      ]);
      final cubit = ActionCenterCubit(repository: repo);
      await cubit.load();

      await tester.pumpWidget(
        wrap(ActionCenterScreen(cubit: cubit)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Battery low'), findsOneWidget);
      expect(find.text('Entered geofence'), findsOneWidget);
      await cubit.close();
    });

    testWidgets('shows empty state when inbox has no items', (tester) async {
      final repo = FakeActionCenterRepository([]);
      final cubit = ActionCenterCubit(repository: repo);
      await cubit.load();

      await tester.pumpWidget(wrap(ActionCenterScreen(cubit: cubit)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('action_center_empty')), findsOneWidget);
      expect(find.text('No proactive items'), findsOneWidget);
      expect(find.text('Battery low'), findsNothing);
      await cubit.close();
    });

    testWidgets('swipe to dismiss removes the item', (tester) async {
      final repo = FakeActionCenterRepository([buildItem(id: 'a1')]);
      final cubit = ActionCenterCubit(repository: repo);
      await cubit.load();

      await tester.pumpWidget(wrap(ActionCenterScreen(cubit: cubit)));
      await tester.pumpAndSettle();

      expect(find.text('Battery low'), findsOneWidget);

      await tester.fling(
        find.byKey(const ValueKey('action_item_a1')),
        const Offset(-400, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(repo.dismissCalls, 1);
      expect(find.text('Battery low'), findsNothing);
      await cubit.close();
    });

    testWidgets('action button triggers executeAction', (tester) async {
      final repo = FakeActionCenterRepository([
        buildItem(id: 'a1', payload: const {'label': 'Charge device'}),
      ]);
      final cubit = ActionCenterCubit(repository: repo);
      await cubit.load();

      await tester.pumpWidget(wrap(ActionCenterScreen(cubit: cubit)));
      await tester.pumpAndSettle();

      // Expand the card to reveal its action button.
      await tester.tap(find.byKey(const Key('action_card_a1')));
      await tester.pumpAndSettle();

      final button = find.byKey(const Key('action_button_a1'));
      expect(button, findsOneWidget);

      await tester.tap(button);
      await tester.pumpAndSettle();

      expect(cubit.state.lastExecutedActionId, 'a1');
      expect(repo.markAsReadCalls, greaterThan(0));
      await cubit.close();
    });
  });
}
