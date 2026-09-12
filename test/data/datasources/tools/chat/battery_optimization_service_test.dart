import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/battery_optimization_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DefaultBatteryOptimizationPlatformWrapper', () {
    late DefaultBatteryOptimizationPlatformWrapper wrapper;

    setUp(() {
      wrapper = DefaultBatteryOptimizationPlatformWrapper();
    });

    test(
        'isIgnoringBatteryOptimizations handles missing platform channel gracefully (returns false on exception)',
        () async {
      final result = await wrapper.isIgnoringBatteryOptimizations();
      expect(result, isFalse);
    });

    test(
        'requestIgnoreBatteryOptimizations handles missing platform channel gracefully (returns false on exception)',
        () async {
      final result = await wrapper.requestIgnoreBatteryOptimizations();
      expect(result, isFalse);
    });
  });

  group('BatteryOptimizationService', () {
    late MockBatteryOptimizationPlatformWrapper mockPlatform;
    late BatteryOptimizationService service;

    setUp(() {
      mockPlatform = MockBatteryOptimizationPlatformWrapper();
      service = BatteryOptimizationService(platformWrapper: mockPlatform);
    });

    group('isBatteryOptimizationDisabled', () {
      test('returns Right(true) when platform wrapper returns true', () async {
        when(() => mockPlatform.isIgnoringBatteryOptimizations())
            .thenAnswer((_) async => true);

        final result = await service.isBatteryOptimizationDisabled();

        expect(result, const Right<Failure, bool>(true));
        verify(() => mockPlatform.isIgnoringBatteryOptimizations()).called(1);
      });

      test('returns Right(false) when platform wrapper returns false', () async {
        when(() => mockPlatform.isIgnoringBatteryOptimizations())
            .thenAnswer((_) async => false);

        final result = await service.isBatteryOptimizationDisabled();

        expect(result, const Right<Failure, bool>(false));
        verify(() => mockPlatform.isIgnoringBatteryOptimizations()).called(1);
      });

      test('returns Left(ServerFailure) when platform wrapper throws', () async {
        when(() => mockPlatform.isIgnoringBatteryOptimizations())
            .thenThrow(Exception('Platform error'));

        final result = await service.isBatteryOptimizationDisabled();

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ServerFailure>());
            expect(failure.message,
                contains('Failed to check battery optimization'));
          },
          (_) => fail('Expected Left'),
        );
        verify(() => mockPlatform.isIgnoringBatteryOptimizations()).called(1);
      });
    });

    group('requestDisableBatteryOptimization', () {
      test('returns Right(true) when platform wrapper returns true', () async {
        when(() => mockPlatform.requestIgnoreBatteryOptimizations())
            .thenAnswer((_) async => true);

        final result = await service.requestDisableBatteryOptimization();

        expect(result, const Right<Failure, bool>(true));
        verify(() => mockPlatform.requestIgnoreBatteryOptimizations()).called(1);
      });

      test('returns Left(ServerFailure) when platform wrapper throws', () async {
        when(() => mockPlatform.requestIgnoreBatteryOptimizations())
            .thenThrow(Exception('Channel failure'));

        final result = await service.requestDisableBatteryOptimization();

        expect(result.isLeft(), isTrue);
        result.fold(
          (failure) {
            expect(failure, isA<ServerFailure>());
            expect(failure.message,
                contains('Failed to request battery optimization disable'));
          },
          (_) => fail('Expected Left'),
        );
        verify(() => mockPlatform.requestIgnoreBatteryOptimizations()).called(1);
      });
    });
  });
}
