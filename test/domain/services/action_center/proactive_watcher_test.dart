import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';
import 'package:flutter_ai_agent/domain/repositories/action_center/action_center_repository.dart';
import 'package:flutter_ai_agent/domain/services/action_center/proactive_watcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockActionCenterRepository extends Mock
    implements ActionCenterRepository {}

class FakeBatteryReader implements AmbientBatteryReader {
  final List<int> levels;
  int _index = 0;
  int readCount = 0;

  FakeBatteryReader(this.levels);

  @override
  Future<int> readBatteryLevel() async {
    readCount++;
    final value = levels[_index.clamp(0, levels.length - 1)];
    if (_index < levels.length - 1) _index++;
    return value;
  }
}

void main() {
  late MockActionCenterRepository repo;
  late int synthCalls;
  final baseTime = DateTime.utc(2026, 1, 1, 12);

  setUpAll(() {
    registerFallbackValue(
      ActionItem(
        id: 'fb',
        title: 't',
        summary: 's',
        timestamp: baseTime,
        source: 'battery_watchdog',
      ),
    );
  });

  setUp(() {
    repo = MockActionCenterRepository();
    synthCalls = 0;
    when(() => repo.addItem(any())).thenAnswer((_) async => const Right(null));
  });

  Future<ActionItem> countingSynthesize(int level) async {
    synthCalls++;
    return ActionItem(
      id: 'battery-$level',
      title: 'Battery changed',
      summary: 'Now at $level percent',
      timestamp: baseTime,
      source: 'battery_watchdog',
    );
  }

  ProactiveWatcher buildWatcher({
    required FakeBatteryReader reader,
    int? lastKnownLevel,
    DateTime? lastWakeAt,
    int minDeltaPct = 5,
    Duration cooldown = const Duration(minutes: 30),
  }) {
    return ProactiveWatcher(
      reader: reader,
      gate: const ZeroTokenGate(),
      repo: repo,
      synthesize: countingSynthesize,
      minDeltaPct: minDeltaPct,
      cooldown: cooldown,
      lastKnownLevel: lastKnownLevel,
      lastWakeAt: lastWakeAt,
    );
  }

  group('ZeroTokenGate', () {
    const gate = ZeroTokenGate();

    test('blocks when delta below minDeltaPct', () {
      expect(
        gate.shouldWake(
          previousValue: 50,
          currentValue: 54,
          minDeltaPct: 5,
          lastWakeAt: null,
          cooldown: const Duration(minutes: 30),
          now: baseTime,
        ),
        isFalse,
      );
    });

    test('passes when delta at threshold and no recent wake', () {
      expect(
        gate.shouldWake(
          previousValue: 50,
          currentValue: 55,
          minDeltaPct: 5,
          lastWakeAt: null,
          cooldown: const Duration(minutes: 30),
          now: baseTime,
        ),
        isTrue,
      );
    });

    test('blocks during cooldown even with big delta', () {
      expect(
        gate.shouldWake(
          previousValue: 50,
          currentValue: 20,
          minDeltaPct: 5,
          lastWakeAt: baseTime,
          cooldown: const Duration(minutes: 30),
          now: baseTime.add(const Duration(minutes: 5)),
        ),
        isFalse,
      );
    });

    test('passes again once cooldown elapsed', () {
      expect(
        gate.shouldWake(
          previousValue: 50,
          currentValue: 20,
          minDeltaPct: 5,
          lastWakeAt: baseTime,
          cooldown: const Duration(minutes: 30),
          now: baseTime.add(const Duration(minutes: 31)),
        ),
        isTrue,
      );
    });
  });

  group('ProactiveWatcher.evaluateBattery', () {
    test('bypasses model call when delta below threshold', () async {
      final reader = FakeBatteryReader([49]);
      final watcher =
          buildWatcher(reader: reader, lastKnownLevel: 50);

      final woke = await watcher.evaluateBattery(now: baseTime);

      expect(woke, isFalse);
      expect(synthCalls, 0);
      expect(reader.readCount, 1);
      verifyNever(() => repo.addItem(any()));
    });

    test('first reading with no baseline does not wake', () async {
      final reader = FakeBatteryReader([80]);
      final watcher = buildWatcher(reader: reader);

      final woke = await watcher.evaluateBattery(now: baseTime);

      expect(woke, isFalse);
      expect(synthCalls, 0);
      expect(watcher.lastKnownLevel, 80);
    });

    test('wakes and posts an item when delta meets threshold', () async {
      final reader = FakeBatteryReader([45]);
      final watcher =
          buildWatcher(reader: reader, lastKnownLevel: 50);

      final woke = await watcher.evaluateBattery(now: baseTime);

      expect(woke, isTrue);
      expect(synthCalls, 1);
      expect(watcher.lastWakeAt, baseTime);
      expect(watcher.lastKnownLevel, 45);
      final posted =
          verify(() => repo.addItem(captureAny())).captured.single as ActionItem;
      expect(posted.source, 'battery_watchdog');
    });

    test('cooldown suppresses a second wake within window', () async {
      final reader = FakeBatteryReader([30, 10]);
      final watcher = buildWatcher(
        reader: reader,
        lastKnownLevel: 60,
        lastWakeAt: baseTime,
      );

      final woke = await watcher.evaluateBattery(
        now: baseTime.add(const Duration(minutes: 10)),
      );

      expect(woke, isFalse);
      expect(synthCalls, 0);
      verifyNever(() => repo.addItem(any()));
    });

    test('wakes again after cooldown elapses', () async {
      final reader = FakeBatteryReader([30]);
      final watcher = buildWatcher(
        reader: reader,
        lastKnownLevel: 60,
        lastWakeAt: baseTime,
      );

      final woke = await watcher.evaluateBattery(
        now: baseTime.add(const Duration(minutes: 45)),
      );

      expect(woke, isTrue);
      expect(synthCalls, 1);
      expect(watcher.lastWakeAt, baseTime.add(const Duration(minutes: 45)));
    });

    test('still records wake when repository write fails after synthesis',
        () async {
      when(() => repo.addItem(any()))
          .thenAnswer((_) async => const Left(CacheFailure('down')));
      final reader = FakeBatteryReader([40]);
      final watcher =
          buildWatcher(reader: reader, lastKnownLevel: 50);

      final woke = await watcher.evaluateBattery(now: baseTime);

      expect(woke, isTrue);
      expect(synthCalls, 1);
      expect(watcher.lastWakeAt, baseTime);
    });
  });
}
