import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final fixedTime = DateTime(2026, 9, 12, 10, 0, 0);

  group('AmbientEventType parsing', () {
    test('toJson returns enum name', () {
      expect(ambientEventTypeToJson(AmbientEventType.batteryLow), 'batteryLow');
      expect(
        ambientEventTypeToJson(AmbientEventType.batteryCritical),
        'batteryCritical',
      );
      expect(
        ambientEventTypeToJson(AmbientEventType.geofenceEnter),
        'geofenceEnter',
      );
      expect(
        ambientEventTypeToJson(AmbientEventType.geofenceExit),
        'geofenceExit',
      );
    });

    test('fromJson parses exact names case-insensitively', () {
      expect(ambientEventTypeFromJson('batteryLow'), AmbientEventType.batteryLow);
      expect(
        ambientEventTypeFromJson('BATTERYCRITICAL'),
        AmbientEventType.batteryCritical,
      );
      expect(
        ambientEventTypeFromJson('geofenceEnter'),
        AmbientEventType.geofenceEnter,
      );
      expect(
        ambientEventTypeFromJson('geofenceExit'),
        AmbientEventType.geofenceExit,
      );
    });

    test('fromJson parses snake_case and aliases', () {
      expect(ambientEventTypeFromJson('battery_low'), AmbientEventType.batteryLow);
      expect(
        ambientEventTypeFromJson('battery_critical'),
        AmbientEventType.batteryCritical,
      );
      expect(
        ambientEventTypeFromJson('geofence_enter'),
        AmbientEventType.geofenceEnter,
      );
      expect(
        ambientEventTypeFromJson('geofence_exit'),
        AmbientEventType.geofenceExit,
      );
      expect(ambientEventTypeFromJson('enter'), AmbientEventType.geofenceEnter);
      expect(ambientEventTypeFromJson('exit'), AmbientEventType.geofenceExit);
      expect(
        ambientEventTypeFromJson('batterylow'),
        AmbientEventType.batteryLow,
      );
    });

    test('fromJson defaults unknown to batteryLow', () {
      expect(ambientEventTypeFromJson('unknown_xyz'), AmbientEventType.batteryLow);
      expect(ambientEventTypeFromJson(null), AmbientEventType.batteryLow);
      expect(ambientEventTypeFromJson(123), AmbientEventType.batteryLow);
    });
  });

  group('GeofenceRegion', () {
    test('supports value equality', () {
      const a = GeofenceRegion(
        id: 'home',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
      );
      const b = GeofenceRegion(
        id: 'home',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
      );
      expect(a, equals(b));
      expect(a.props, ['home', 1.0, 2.0, 100.0]);
      expect(a.copyWith(), equals(a));
    });

    test('copyWith updates specified fields', () {
      const region = GeofenceRegion(
        id: 'home',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
      );
      final copy = region.copyWith(
        id: 'work',
        latitude: 3.0,
        longitude: 4.0,
        radiusMeters: 250.0,
      );
      expect(copy.id, 'work');
      expect(copy.latitude, 3.0);
      expect(copy.longitude, 4.0);
      expect(copy.radiusMeters, 250.0);
    });

    test('toJson / fromJson roundtrip', () {
      const region = GeofenceRegion(
        id: 'home',
        latitude: 1.5,
        longitude: 2.5,
        radiusMeters: 150.0,
      );
      final restored = GeofenceRegion.fromJson(region.toJson());
      expect(restored, equals(region));
    });

    test('fromJson supports lat/lng and radius aliases', () {
      final region = GeofenceRegion.fromJson({
        'id': 'office',
        'lat': 10.0,
        'lng': 20.0,
        'radius': 300,
      });
      expect(region.id, 'office');
      expect(region.latitude, 10.0);
      expect(region.longitude, 20.0);
      expect(region.radiusMeters, 300.0);
    });

    test('fromJson supports radius_meters alias and string numbers', () {
      final region = GeofenceRegion.fromJson({
        'id': 'shop',
        'latitude': '1.25',
        'longitude': '2.75',
        'radius_meters': '200.5',
      });
      expect(region.latitude, 1.25);
      expect(region.longitude, 2.75);
      expect(region.radiusMeters, 200.5);
    });

    test('fromJson defaults missing or invalid fields', () {
      final empty = GeofenceRegion.fromJson({});
      expect(empty.id, isEmpty);
      expect(empty.latitude, 0.0);
      expect(empty.longitude, 0.0);
      expect(empty.radiusMeters, 100.0);

      final invalid = GeofenceRegion.fromJson({
        'id': null,
        'latitude': 'not-a-number',
        'longitude': true,
        'radiusMeters': 'bad',
      });
      expect(invalid.latitude, 0.0);
      expect(invalid.longitude, 0.0);
      expect(invalid.radiusMeters, 100.0);
    });
  });

  group('AmbientEvent', () {
    test('supports value equality', () {
      final a = AmbientEvent(
        id: 'e1',
        type: AmbientEventType.batteryLow,
        title: 'Battery low',
        body: 'Low',
        timestamp: fixedTime,
        batteryLevel: 15,
      );
      final b = AmbientEvent(
        id: 'e1',
        type: AmbientEventType.batteryLow,
        title: 'Battery low',
        body: 'Low',
        timestamp: fixedTime,
        batteryLevel: 15,
      );
      expect(a, equals(b));
      expect(a.props.length, 7);
      expect(a.copyWith(), equals(a));
    });

    test('copyWith updates specified fields', () {
      final event = AmbientEvent(
        id: 'e1',
        type: AmbientEventType.batteryLow,
        title: 't',
        body: 'b',
        timestamp: fixedTime,
      );
      final copy = event.copyWith(
        id: 'e2',
        type: AmbientEventType.geofenceEnter,
        title: 't2',
        body: 'b2',
        timestamp: fixedTime.add(const Duration(minutes: 1)),
        regionId: 'home',
        batteryLevel: 9,
      );
      expect(copy.id, 'e2');
      expect(copy.type, AmbientEventType.geofenceEnter);
      expect(copy.title, 't2');
      expect(copy.body, 'b2');
      expect(copy.regionId, 'home');
      expect(copy.batteryLevel, 9);
    });

    test('toJson includes optionals when present', () {
      final event = AmbientEvent(
        id: 'e1',
        type: AmbientEventType.geofenceEnter,
        title: 'Entered home',
        body: 'Entered geofence home.',
        timestamp: fixedTime,
        regionId: 'home',
      );
      final json = event.toJson();
      expect(json['id'], 'e1');
      expect(json['type'], 'geofenceEnter');
      expect(json['regionId'], 'home');
      expect(json.containsKey('batteryLevel'), isFalse);
    });

    test('toJson omits null optionals', () {
      final event = AmbientEvent(
        id: 'e1',
        type: AmbientEventType.batteryLow,
        title: 't',
        body: 'b',
        timestamp: fixedTime,
      );
      final json = event.toJson();
      expect(json.containsKey('regionId'), isFalse);
      expect(json.containsKey('batteryLevel'), isFalse);
    });

    test('fromJson roundtrips toJson output', () {
      final event = AmbientEvent(
        id: 'e1',
        type: AmbientEventType.batteryCritical,
        title: 'Battery critical',
        body: 'Critical',
        timestamp: fixedTime,
        batteryLevel: 8,
      );
      final restored = AmbientEvent.fromJson(event.toJson());
      expect(restored, equals(event));
    });

    test('fromJson parses epoch millis timestamp', () {
      final event = AmbientEvent.fromJson({
        'id': 'e1',
        'type': 'batteryLow',
        'title': 't',
        'body': 'b',
        'timestamp': fixedTime.millisecondsSinceEpoch,
        'batteryLevel': 15,
      });
      expect(event.timestamp, fixedTime);
      expect(event.batteryLevel, 15);
    });

    test('fromJson handles invalid timestamp and battery', () {
      final event = AmbientEvent.fromJson({
        'id': 'e1',
        'type': 'batteryLow',
        'title': 't',
        'body': 'b',
        'timestamp': 'not-a-date',
        'batteryLevel': 'bad',
      });
      expect(
        event.timestamp,
        DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(event.batteryLevel, isNull);
    });

    test('fromJson handles missing timestamp and numeric battery string', () {
      final event = AmbientEvent.fromJson({
        'id': 'e1',
        'type': 'batteryLow',
        'title': 't',
        'body': 'b',
        'batteryLevel': '15',
      });
      expect(
        event.timestamp,
        DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(event.batteryLevel, 15);
    });

    test('fromJson supports snake_case region and battery keys', () {
      final event = AmbientEvent.fromJson({
        'id': 'e1',
        'type': 'geofence_enter',
        'title': 't',
        'body': 'b',
        'timestamp': fixedTime.toIso8601String(),
        'region_id': 'home',
        'battery_level': 50,
      });
      expect(event.regionId, 'home');
      expect(event.batteryLevel, 50);
      expect(event.type, AmbientEventType.geofenceEnter);
    });

    test('fromJson defaults missing fields', () {
      final event = AmbientEvent.fromJson({});
      expect(event.id, isEmpty);
      expect(event.title, isEmpty);
      expect(event.body, isEmpty);
      expect(event.regionId, isNull);
      expect(event.batteryLevel, isNull);
    });
  });

  group('AmbientCheckResult', () {
    test('empty factory returns non-triggered result', () {
      final empty = AmbientCheckResult.empty(checkedAt: fixedTime);
      expect(empty.triggered, isFalse);
      expect(empty.events, isEmpty);
      expect(empty.checkedAt, fixedTime);
    });

    test('empty factory defaults checkedAt to epoch', () {
      final empty = AmbientCheckResult.empty();
      expect(
        empty.checkedAt,
        DateTime.fromMillisecondsSinceEpoch(0),
      );
    });

    test('supports value equality and copyWith', () {
      final event = AmbientEvent(
        id: 'e1',
        type: AmbientEventType.batteryLow,
        title: 't',
        body: 'b',
        timestamp: fixedTime,
      );
      final a = AmbientCheckResult(
        triggered: true,
        events: [event],
        checkedAt: fixedTime,
      );
      final b = AmbientCheckResult(
        triggered: true,
        events: [event],
        checkedAt: fixedTime,
      );
      expect(a, equals(b));
      expect(a.props.length, 3);
      expect(a.copyWith(), equals(a));
      final copy = a.copyWith(
        triggered: false,
        events: const [],
        checkedAt: fixedTime.add(const Duration(minutes: 5)),
      );
      expect(copy.triggered, isFalse);
      expect(copy.events, isEmpty);
    });

    test('toJson / fromJson roundtrip', () {
      final event = AmbientEvent(
        id: 'e1',
        type: AmbientEventType.geofenceExit,
        title: 'Exited',
        body: 'Exited home.',
        timestamp: fixedTime,
        regionId: 'home',
      );
      final result = AmbientCheckResult(
        triggered: true,
        events: [event],
        checkedAt: fixedTime,
      );
      final restored = AmbientCheckResult.fromJson(result.toJson());
      expect(restored, equals(result));
    });

    test('fromJson infers triggered from events when missing', () {
      final event = AmbientEvent(
        id: 'e1',
        type: AmbientEventType.batteryLow,
        title: 't',
        body: 'b',
        timestamp: fixedTime,
      );
      final withEvents = AmbientCheckResult.fromJson({
        'events': [event.toJson()],
        'checkedAt': fixedTime.toIso8601String(),
      });
      expect(withEvents.triggered, isTrue);

      final withoutEvents = AmbientCheckResult.fromJson({
        'events': [],
        'checkedAt': fixedTime.toIso8601String(),
      });
      expect(withoutEvents.triggered, isFalse);
    });

    test('fromJson parses epoch and snake_case checkedAt', () {
      final epoch = AmbientCheckResult.fromJson({
        'triggered': false,
        'events': [],
        'checkedAt': fixedTime.millisecondsSinceEpoch,
      });
      expect(epoch.checkedAt, fixedTime);

      final snake = AmbientCheckResult.fromJson({
        'triggered': false,
        'events': [],
        'checked_at': fixedTime.toIso8601String(),
      });
      expect(snake.checkedAt, fixedTime);
    });

    test('fromJson defaults invalid checkedAt to epoch', () {
      final invalid = AmbientCheckResult.fromJson({
        'triggered': false,
        'events': [],
        'checkedAt': 'bad-date',
      });
      expect(
        invalid.checkedAt,
        DateTime.fromMillisecondsSinceEpoch(0),
      );

      final missing = AmbientCheckResult.fromJson({
        'triggered': true,
        'events': [],
      });
      expect(
        missing.checkedAt,
        DateTime.fromMillisecondsSinceEpoch(0),
      );
    });

    test('fromJson ignores non-map event entries', () {
      final result = AmbientCheckResult.fromJson({
        'triggered': true,
        'events': ['bad', 123, null],
        'checkedAt': fixedTime.toIso8601String(),
      });
      expect(result.events, isEmpty);
    });
  });
}
