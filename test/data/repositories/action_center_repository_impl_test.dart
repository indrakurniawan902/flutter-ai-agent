import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_ai_agent/common/exception.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/local/action_center/action_center_datasource.dart';
import 'package:flutter_ai_agent/data/models/action_center/action_item_model.dart';
import 'package:flutter_ai_agent/data/repositories/action_center_repository_impl.dart';
import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';

class MockActionCenterDatasource extends Mock
    implements ActionCenterDatasource {}

void main() {
  late MockActionCenterDatasource mockDatasource;
  late ActionCenterRepositoryImpl repository;

  final item = ActionItemModel(
    id: 'a1',
    title: 'Battery low',
    summary: 'Below 20 percent',
    timestamp: DateTime.utc(2026, 1, 1),
    priority: ActionItemPriority.high,
    source: 'battery_watchdog',
  );

  setUp(() {
    mockDatasource = MockActionCenterDatasource();
    repository = ActionCenterRepositoryImpl(datasource: mockDatasource);
    registerFallbackValue(item);
  });

  group('getItems', () {
    test('returns Right with datasource items on success', () async {
      when(() => mockDatasource.getItems())
          .thenAnswer((_) async => [item]);

      final result = await repository.getItems();

      expect(result, isA<Right<Failure, List<ActionItem>>>());
      result.fold(
        (_) => fail('expected Right'),
        (items) {
          expect(items, hasLength(1));
          expect(items.first.id, 'a1');
        },
      );
      verify(() => mockDatasource.getItems()).called(1);
    });

    test('returns Left CacheFailure when datasource throws CacheException',
        () async {
      when(() => mockDatasource.getItems())
          .thenThrow(const CacheException('boom'));

      final result = await repository.getItems();

      expect(result, isA<Left<Failure, List<ActionItem>>>());
      result.fold(
        (failure) => expect(failure, isA<CacheFailure>()),
        (_) => fail('expected Left'),
      );
    });

    test('returns Left CacheFailure for unexpected error', () async {
      when(() => mockDatasource.getItems()).thenThrow(Exception('oops'));

      final result = await repository.getItems();

      expect(result, isA<Left<Failure, List<ActionItem>>>());
    });
  });

  group('addItem', () {
    test('returns Right and forwards a model built from the entity',
        () async {
      when(() => mockDatasource.addItem(any())).thenAnswer((_) async {});

      final entity = ActionItem(
        id: 'a2',
        title: 'Geofence',
        summary: 'Entered zone',
        timestamp: DateTime.utc(2026, 2, 2),
        source: 'geofence',
      );
      final result = await repository.addItem(entity);

      expect(result, isA<Right<Failure, void>>());
      final captured =
          verify(() => mockDatasource.addItem(captureAny())).captured;
      final passed = captured.single as ActionItemModel;
      expect(passed.id, 'a2');
      expect(passed.source, 'geofence');
    });

    test('returns Left CacheFailure when datasource throws', () async {
      when(() => mockDatasource.addItem(any()))
          .thenThrow(const CacheException('write failed'));

      final result = await repository.addItem(item);

      expect(result, isA<Left<Failure, void>>());
      result.fold(
        (failure) => expect(failure, isA<CacheFailure>()),
        (_) => fail('expected Left'),
      );
    });
  });

  group('markAsRead', () {
    test('returns Right on success', () async {
      when(() => mockDatasource.markAsRead('a1')).thenAnswer((_) async {});

      final result = await repository.markAsRead('a1');

      expect(result, isA<Right<Failure, void>>());
      verify(() => mockDatasource.markAsRead('a1')).called(1);
    });

    test('returns Left CacheFailure when datasource throws', () async {
      when(() => mockDatasource.markAsRead('a1'))
          .thenThrow(const CacheException('nope'));

      final result = await repository.markAsRead('a1');

      expect(result, isA<Left<Failure, void>>());
    });
  });

  group('dismiss', () {
    test('returns Right on success', () async {
      when(() => mockDatasource.dismiss('a1')).thenAnswer((_) async {});

      final result = await repository.dismiss('a1');

      expect(result, isA<Right<Failure, void>>());
      verify(() => mockDatasource.dismiss('a1')).called(1);
    });

    test('returns Left CacheFailure when datasource throws', () async {
      when(() => mockDatasource.dismiss('a1'))
          .thenThrow(const CacheException('nope'));

      final result = await repository.dismiss('a1');

      expect(result, isA<Left<Failure, void>>());
    });
  });

  group('clearAll', () {
    test('returns Right on success', () async {
      when(() => mockDatasource.clearAll()).thenAnswer((_) async {});

      final result = await repository.clearAll();

      expect(result, isA<Right<Failure, void>>());
      verify(() => mockDatasource.clearAll()).called(1);
    });

    test('returns Left CacheFailure when datasource throws', () async {
      when(() => mockDatasource.clearAll())
          .thenThrow(const CacheException('nope'));

      final result = await repository.clearAll();

      expect(result, isA<Left<Failure, void>>());
    });
  });
}
