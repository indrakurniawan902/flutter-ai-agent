import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';
import 'package:flutter_ai_agent/domain/repositories/action_center/action_center_repository.dart';
import 'package:flutter_ai_agent/presentation/screen/action_center/cubit/action_center_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/action_center/cubit/action_center_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockActionCenterRepository extends Mock
    implements ActionCenterRepository {}

void main() {
  late MockActionCenterRepository repo;
  late ActionCenterCubit cubit;

  ActionItem buildItem({
    String id = 'a1',
    DateTime? timestamp,
    bool isRead = false,
    Map<String, dynamic>? payload,
    String source = 'battery_watchdog',
  }) {
    return ActionItem(
      id: id,
      title: 'Battery low',
      summary: 'Below 20 percent',
      timestamp: timestamp ?? DateTime.utc(2026, 1, 1),
      isRead: isRead,
      actionPayload: payload,
      source: source,
    );
  }

  setUp(() {
    repo = MockActionCenterRepository();
    cubit = ActionCenterCubit(repository: repo);
    registerFallbackValue(buildItem(id: 'fallback'));
  });

  tearDown(() async {
    await cubit.close();
  });

  group('initial state', () {
    test('empty inbox, not loading, no error', () {
      expect(cubit.state, const ActionCenterState());
      expect(cubit.state.items, isEmpty);
      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.error, isNull);
    });
  });

  group('load', () {
    test('emits items newest-first on success and clears loading', () async {
      final items = [
        buildItem(id: 'new', timestamp: DateTime.utc(2026, 3, 1)),
        buildItem(id: 'old', timestamp: DateTime.utc(2026, 1, 1)),
      ];
      when(() => repo.getItems()).thenAnswer((_) async => Right(items));

      await cubit.load();

      expect(cubit.state.isLoading, isFalse);
      expect(cubit.state.error, isNull);
      expect(cubit.state.items.map((e) => e.id).toList(), ['new', 'old']);
    });

    test('emits error on Left failure', () async {
      when(() => repo.getItems())
          .thenAnswer((_) async => const Left(CacheFailure('boom')));

      await cubit.load();

      expect(cubit.state.items, isEmpty);
      expect(cubit.state.error, 'boom');
      expect(cubit.state.isLoading, isFalse);
    });
  });

  group('postItem', () {
    test('adds item then reloads inbox', () async {
      final item = buildItem(id: 'posted');
      when(() => repo.addItem(any())).thenAnswer((_) async => const Right(null));
      when(() => repo.getItems()).thenAnswer((_) async => Right([item]));

      await cubit.postItem(item);

      verify(() => repo.addItem(item)).called(1);
      verify(() => repo.getItems()).called(1);
      expect(cubit.state.items.map((e) => e.id).toList(), ['posted']);
    });

    test('surfaces failure and does not reload', () async {
      final item = buildItem(id: 'posted');
      when(() => repo.addItem(any()))
          .thenAnswer((_) async => const Left(CacheFailure('nope')));

      await cubit.postItem(item);

      expect(cubit.state.error, 'nope');
      verifyNever(() => repo.getItems());
    });
  });

  group('markAsRead', () {
    test('reloads after success', () async {
      when(() => repo.markAsRead('a1')).thenAnswer((_) async => const Right(null));
      when(() => repo.getItems())
          .thenAnswer((_) async => Right([buildItem(id: 'a1', isRead: true)]));

      await cubit.markAsRead('a1');

      verify(() => repo.markAsRead('a1')).called(1);
      expect(cubit.state.items.single.isRead, isTrue);
    });

    test('surfaces failure', () async {
      when(() => repo.markAsRead('a1'))
          .thenAnswer((_) async => const Left(CacheFailure('gone')));

      await cubit.markAsRead('a1');

      expect(cubit.state.error, 'gone');
    });
  });

  group('dismiss', () {
    test('reloads after success', () async {
      when(() => repo.dismiss('a1')).thenAnswer((_) async => const Right(null));
      when(() => repo.getItems()).thenAnswer((_) async => const Right([]));

      await cubit.dismiss('a1');

      verify(() => repo.dismiss('a1')).called(1);
      expect(cubit.state.items, isEmpty);
    });

    test('surfaces failure', () async {
      when(() => repo.dismiss('a1'))
          .thenAnswer((_) async => const Left(CacheFailure('gone')));

      await cubit.dismiss('a1');

      expect(cubit.state.error, 'gone');
    });
  });

  group('executeAction', () {
    test('generic action marks read and records lastExecutedActionId',
        () async {
      final item = buildItem(id: 'run-me');
      when(() => repo.markAsRead('run-me'))
          .thenAnswer((_) async => const Right(null));
      when(() => repo.getItems())
          .thenAnswer((_) async => Right([buildItem(id: 'run-me', isRead: true)]));

      await cubit.executeAction(item);

      verify(() => repo.markAsRead('run-me')).called(1);
      expect(cubit.state.lastExecutedActionId, 'run-me');
      expect(cubit.state.items.single.isRead, isTrue);
    });

    test('open_settings action marks read but records no executed id',
        () async {
      final item = buildItem(id: 'cfg', payload: const {'open_settings': true});
      when(() => repo.markAsRead('cfg'))
          .thenAnswer((_) async => const Right(null));
      when(() => repo.getItems())
          .thenAnswer((_) async => Right([buildItem(id: 'cfg', isRead: true, payload: const {'open_settings': true})]));

      await cubit.executeAction(item);

      verify(() => repo.markAsRead('cfg')).called(1);
      expect(cubit.state.lastExecutedActionId, isNull);
    });
  });
}
