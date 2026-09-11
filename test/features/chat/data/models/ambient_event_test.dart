import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/features/chat/data/models/ambient_event.dart';

void main() {
  group('GeofenceRegion Model', () {
    const region1 = GeofenceRegion(
      id: 'office_1',
      name: 'HQ Office',
      latitude: -6.200000,
      longitude: 106.816666,
      radiusMeters: 200.0,
      triggerOnEnter: true,
      triggerOnExit: true,
    );

    const region2 = GeofenceRegion(
      id: 'office_1',
      name: 'HQ Office',
      latitude: -6.200000,
      longitude: 106.816666,
      radiusMeters: 200.0,
      triggerOnEnter: true,
      triggerOnExit: true,
    );

    test('supports value equality', () {
      expect(region1, equals(region2));
      expect(
        region1,
        isNot(equals(region1.copyWith(name: 'Branch Office'))),
      );
    });

    test('copyWith copies and overrides fields', () {
      final updated = region1.copyWith(
        radiusMeters: 300.0,
        triggerOnExit: false,
      );
      expect(updated.id, 'office_1');
      expect(updated.radiusMeters, 300.0);
      expect(updated.triggerOnExit, false);
      expect(updated.triggerOnEnter, true);
    });

    test('toJson and fromJson serialize and deserialize correctly', () {
      final json = region1.toJson();
      expect(json['id'], 'office_1');
      expect(json['name'], 'HQ Office');
      expect(json['latitude'], -6.200000);
      expect(json['longitude'], 106.816666);
      expect(json['radius_meters'], 200.0);
      expect(json['trigger_on_enter'], true);
      expect(json['trigger_on_exit'], true);

      final deserialized = GeofenceRegion.fromJson(json);
      expect(deserialized, equals(region1));
    });

    test('fromJson handles snake_case and camelCase keys with default fallback', () {
      final json = {
        'id': 'home',
        'name': 'Home',
        'latitude': -6.123,
        'longitude': 106.456,
      };
      final region = GeofenceRegion.fromJson(json);
      expect(region.id, 'home');
      expect(region.radiusMeters, 200.0);
      expect(region.triggerOnEnter, true);
      expect(region.triggerOnExit, false);
    });
  });

  group('AmbientEvent Model', () {
    final timestamp = DateTime.utc(2026, 9, 11, 10, 0, 0);
    final event1 = AmbientEvent(
      id: 'evt_1',
      type: AmbientEventType.batteryLow,
      timestamp: timestamp,
      title: 'Battery Low (14%)',
      body: 'Battery is below 15%. Consider enabling battery saver.',
      payload: const {'battery_level': 14, 'is_charging': false},
      recommendedAction: 'Enable battery saver mode',
    );

    final event2 = AmbientEvent(
      id: 'evt_1',
      type: AmbientEventType.batteryLow,
      timestamp: timestamp,
      title: 'Battery Low (14%)',
      body: 'Battery is below 15%. Consider enabling battery saver.',
      payload: const {'battery_level': 14, 'is_charging': false},
      recommendedAction: 'Enable battery saver mode',
    );

    test('supports value equality', () {
      expect(event1, equals(event2));
      expect(
        event1,
        isNot(equals(event1.copyWith(title: 'Other Title'))),
      );
    });

    test('toJson and fromJson serialize and deserialize correctly', () {
      final json = event1.toJson();
      expect(json['id'], 'evt_1');
      expect(json['type'], 'batteryLow');
      expect(json['timestamp'], timestamp.toIso8601String());
      expect(json['title'], 'Battery Low (14%)');
      expect(json['payload']['battery_level'], 14);
      expect(json['recommended_action'], 'Enable battery saver mode');

      final deserialized = AmbientEvent.fromJson(json);
      expect(deserialized, equals(event1));
    });
  });

  group('AmbientCheckResult Model', () {
    final timestamp = DateTime.utc(2026, 9, 11, 10, 0, 0);
    final event = AmbientEvent(
      id: 'evt_1',
      type: AmbientEventType.geofenceEnter,
      timestamp: timestamp,
      title: 'Arrived at Office',
      body: 'Daily briefing ready',
      payload: const {'region_id': 'office_1'},
    );

    final result = AmbientCheckResult(
      batteryLevel: 80,
      isCharging: false,
      currentPosition: const {'latitude': -6.2, 'longitude': 106.8},
      triggeredEvents: [event],
      timestamp: timestamp,
    );

    test('supports value equality', () {
      final result2 = AmbientCheckResult(
        batteryLevel: 80,
        isCharging: false,
        currentPosition: const {'latitude': -6.2, 'longitude': 106.8},
        triggeredEvents: [event],
        timestamp: timestamp,
      );
      expect(result, equals(result2));
    });

    test('toJson and fromJson serialize correctly', () {
      final json = result.toJson();
      expect(json['battery_level'], 80);
      expect(json['is_charging'], false);
      expect(json['triggered_events'].length, 1);

      final deserialized = AmbientCheckResult.fromJson(json);
      expect(deserialized, equals(result));
    });
  });
}
