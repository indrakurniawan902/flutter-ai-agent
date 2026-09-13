import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/exception.dart';
import 'package:flutter_ai_agent/data/datasources/local/action_center/action_center_datasource.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/data/models/action_center/action_item_model.dart';
import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../helpers/mocks.dart';

class MockActionCenterDatasource extends Mock
    implements ActionCenterDatasource {}

void main() {
  late MockBatteryPlatformWrapper mockBattery;
  late MockWorkmanagerPlatformWrapper mockWorkmanager;
  late MockActionCenterDatasource mockActionCenter;

  final fixedTime = DateTime(2026, 9, 12, 10, 0, 0);

  const homeRegion = GeofenceRegion(
    id: 'home',
    latitude: 1.0,
    longitude: 2.0,
    radiusMeters: 200.0,
  );

  setUpAll(() {
    registerFallbackValue(
      ActionItemModel(
        id: 'fallback',
        title: 'fallback',
        summary: 'fallback',
        timestamp: fixedTime,
        source: 'fallback',
      ),
    );
  });

  setUp(() {
    mockBattery = MockBatteryPlatformWrapper();
    mockWorkmanager = MockWorkmanagerPlatformWrapper();
    mockActionCenter = MockActionCenterDatasource();
    when(() => mockActionCenter.addItem(any())).thenAnswer((_) async {});
  });

  void stubBattery({required int level, required bool charging}) {
    when(() => mockBattery.getBatteryLevel()).thenAnswer((_) async => level);
    when(() => mockBattery.isCharging()).thenAnswer((_) async => charging);
  }

  AmbientTriggerService buildService({
    ActionCenterDatasource? actionCenter,
    List<GeofenceRegion>? regions,
  }) {
    return AmbientTriggerService(
      battery: mockBattery,
      workmanager: mockWorkmanager,
      initialRegions: regions,
      actionCenterDatasource: actionCenter,
    );
  }

  ActionItemModel mirroredSingle() {
    final captured =
        verify(() => mockActionCenter.addItem(captureAny())).captured;
    expect(captured, hasLength(1));
    return captured.single as ActionItemModel;
  }

  group('ambient check -> Action Center mirror', () {
    test('battery critical event is mirrored as unread high-priority item',
        () async {
      stubBattery(level: 5, charging: false);
      final service = buildService(actionCenter: mockActionCenter);

      final result = await service.checkBattery(now: fixedTime);

      expect(result, isA<Either<Object, AmbientCheckResult>>());
      final events = result.getOrElse(() => AmbientCheckResult.empty()).events;
      expect(events, hasLength(1));

      final item = mirroredSingle();
      expect(item.id, events.first.id);
      expect(item.title, 'Battery critical');
      expect(item.summary, events.first.body);
      expect(item.timestamp, events.first.timestamp);
      expect(item.priority, ActionItemPriority.high);
      expect(item.isRead, isFalse);
      expect(item.source, 'battery_watchdog');
      expect(item.actionPayload, {'batteryLevel': 5});
    });

    test('battery low event is mirrored with normal priority', () async {
      stubBattery(level: 15, charging: false);
      final service = buildService(actionCenter: mockActionCenter);

      final result = await service.checkBattery(now: fixedTime);
      final events = result.getOrElse(() => AmbientCheckResult.empty()).events;
      expect(events.first.type, AmbientEventType.batteryLow);

      final item = mirroredSingle();
      expect(item.priority, ActionItemPriority.normal);
      expect(item.isRead, isFalse);
      expect(item.source, 'battery_watchdog');
      expect(item.actionPayload, {'batteryLevel': 15});
    });

    test('geofence enter event is mirrored with geofence source', () async {
      final service =
          buildService(actionCenter: mockActionCenter, regions: [homeRegion]);

      final result = await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );
      final events = result.getOrElse(() => AmbientCheckResult.empty()).events;
      expect(events.first.type, AmbientEventType.geofenceEnter);

      final item = mirroredSingle();
      expect(item.id, events.first.id);
      expect(item.priority, ActionItemPriority.normal);
      expect(item.isRead, isFalse);
      expect(item.source, 'geofence');
      expect(item.actionPayload, {'type': 'geofenceEnter'});
    });

    test('checkAll mirrors each triggered event exactly once', () async {
      stubBattery(level: 5, charging: false);
      final service =
          buildService(actionCenter: mockActionCenter, regions: [homeRegion]);

      final result = await service.checkAll(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );
      final events = result.getOrElse(() => AmbientCheckResult.empty()).events;
      expect(events, hasLength(2));

      final ids = verify(() => mockActionCenter.addItem(captureAny()))
          .captured
          .cast<ActionItemModel>()
          .map((i) => i.id)
          .toList();
      expect(ids, events.map((e) => e.id).toList());
    });

    test('non-triggered check mirrors nothing', () async {
      stubBattery(level: 90, charging: false);
      final service = buildService(actionCenter: mockActionCenter);

      final result = await service.checkBattery(now: fixedTime);

      expect(result.getOrElse(() => AmbientCheckResult.empty()).triggered, isFalse);
      verifyNever(() => mockActionCenter.addItem(any()));
    });
  });

  group('mirror failure isolation', () {
    test('datasource failure does not change the returned AmbientCheckResult',
        () async {
      stubBattery(level: 5, charging: false);
      when(() => mockActionCenter.addItem(any()))
          .thenThrow(CacheException('box write failed'));
      final service = buildService(actionCenter: mockActionCenter);

      final result = await service.checkBattery(now: fixedTime);

      expect(result.isRight(), isTrue);
      final check = result.getOrElse(() => AmbientCheckResult.empty());
      expect(check.triggered, isTrue);
      expect(check.events, hasLength(1));
      expect(check.events.first.type, AmbientEventType.batteryCritical);
      expect(check.checkedAt, fixedTime);
    });

    test('geofence mirror failure does not change the check result', () async {
      when(() => mockActionCenter.addItem(any()))
          .thenThrow(Exception('hive down'));
      final service =
          buildService(actionCenter: mockActionCenter, regions: [homeRegion]);

      final result = await service.checkGeofence(
        latitude: 1.0,
        longitude: 2.0,
        now: fixedTime,
      );

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => AmbientCheckResult.empty()).triggered, isTrue);
    });

    test('service without datasource still returns the same result', () async {
      stubBattery(level: 5, charging: false);
      final service = buildService();

      final result = await service.checkBattery(now: fixedTime);

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => AmbientCheckResult.empty()).events,
          hasLength(1));
      verifyZeroInteractions(mockActionCenter);
    });
  });
}
