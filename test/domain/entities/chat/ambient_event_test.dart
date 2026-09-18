import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/services/geofence/geofence_action_dispatcher.dart';
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
    test('supports value equality and defaults', () {
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
      expect(a.props, [
        'home',
        'home',
        1.0,
        2.0,
        100.0,
        true,
        GeofenceAction.none,
        '',
        GeofenceActionTrigger.both,
      ]);
      expect(a.name, 'home');
      expect(a.displayName, 'home');
      expect(a.isEnabled, isTrue);
      expect(a.copyWith(), equals(a));

      const custom = GeofenceRegion(
        id: 'work',
        name: 'Workplace',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
        isEnabled: false,
      );
      expect(custom.name, 'Workplace');
      expect(custom.displayName, 'Workplace');
      expect(custom.isEnabled, isFalse);
      expect(custom.props, [
        'work',
        'Workplace',
        1.0,
        2.0,
        100.0,
        false,
        GeofenceAction.none,
        '',
        GeofenceActionTrigger.both,
      ]);
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
        name: 'Workplace',
        latitude: 3.0,
        longitude: 4.0,
        radiusMeters: 250.0,
        isEnabled: false,
      );
      expect(copy.id, 'work');
      expect(copy.name, 'Workplace');
      expect(copy.latitude, 3.0);
      expect(copy.longitude, 4.0);
      expect(copy.radiusMeters, 250.0);
      expect(copy.isEnabled, isFalse);
    });

    test('toJson / fromJson roundtrip', () {
      const region = GeofenceRegion(
        id: 'home',
        name: 'My House',
        latitude: 1.5,
        longitude: 2.5,
        radiusMeters: 150.0,
        isEnabled: false,
      );
      final restored = GeofenceRegion.fromJson(region.toJson());
      expect(restored, equals(region));
      expect(restored.name, 'My House');
      expect(restored.isEnabled, isFalse);
    });

    test('fromJson supports lat/lng and radius aliases', () {
      final region = GeofenceRegion.fromJson({
        'id': 'office',
        'lat': 10.0,
        'lng': 20.0,
        'radius': 300,
      });
      expect(region.id, 'office');
      expect(region.name, 'office');
      expect(region.latitude, 10.0);
      expect(region.longitude, 20.0);
      expect(region.radiusMeters, 300.0);
      expect(region.isEnabled, isTrue);
    });

    test('fromJson supports label and active aliases', () {
      final region = GeofenceRegion.fromJson({
        'id': 'office',
        'label': 'Main Office',
        'lat': 10.0,
        'lng': 20.0,
        'radius': 300,
        'active': false,
      });
      expect(region.id, 'office');
      expect(region.name, 'Main Office');
      expect(region.latitude, 10.0);
      expect(region.longitude, 20.0);
      expect(region.radiusMeters, 300.0);
      expect(region.isEnabled, isFalse);
    });

    test('fromJson supports string booleans and is_enabled / active keys', () {
      final r1 = GeofenceRegion.fromJson({
        'id': 'r1',
        'is_enabled': 'false',
      });
      expect(r1.isEnabled, isFalse);

      final r2 = GeofenceRegion.fromJson({
        'id': 'r2',
        'active': 'true',
      });
      expect(r2.isEnabled, isTrue);

      final r3 = GeofenceRegion.fromJson({
        'id': 'r3',
        'isEnabled': true,
        'name': 'Custom',
      });
      expect(r3.name, 'Custom');
      expect(r3.isEnabled, isTrue);
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
      expect(empty.name, isEmpty);
      expect(empty.latitude, 0.0);
      expect(empty.longitude, 0.0);
      expect(empty.radiusMeters, 100.0);
      expect(empty.isEnabled, isTrue);

      final invalid = GeofenceRegion.fromJson({
        'id': null,
        'latitude': 'not-a-number',
        'longitude': true,
        'radiusMeters': 'bad',
        'isEnabled': 'invalid_bool',
      });
      expect(invalid.latitude, 0.0);
      expect(invalid.longitude, 0.0);
      expect(invalid.radiusMeters, 100.0);
      expect(invalid.isEnabled, isTrue);
    });
  });

  group('GeofenceRegion action binding', () {
    test('defaults to no action, empty payload, both triggers', () {
      const region = GeofenceRegion(
        id: 'home',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
      );
      expect(region.action, GeofenceAction.none);
      expect(region.actionPayload, isEmpty);
      expect(region.actionOn, GeofenceActionTrigger.both);
    });

    test('toJson / fromJson roundtrip preserves action binding', () {
      const runPrompt = GeofenceRegion(
        id: 'work',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
        action: GeofenceAction.runPrompt,
        actionPayload: 'Start focus mode',
        actionOn: GeofenceActionTrigger.enter,
      );
      final restoredRun = GeofenceRegion.fromJson(runPrompt.toJson());
      expect(restoredRun, equals(runPrompt));
      expect(restoredRun.action, GeofenceAction.runPrompt);
      expect(restoredRun.actionPayload, 'Start focus mode');
      expect(restoredRun.actionOn, GeofenceActionTrigger.enter);

      const openUrl = GeofenceRegion(
        id: 'gym',
        latitude: 3.0,
        longitude: 4.0,
        radiusMeters: 50.0,
        action: GeofenceAction.openUrl,
        actionPayload: 'https://example.com',
        actionOn: GeofenceActionTrigger.exit,
      );
      final restoredUrl = GeofenceRegion.fromJson(openUrl.toJson());
      expect(restoredUrl, equals(openUrl));
      expect(restoredUrl.action, GeofenceAction.openUrl);
      expect(restoredUrl.actionPayload, 'https://example.com');
      expect(restoredUrl.actionOn, GeofenceActionTrigger.exit);
    });

    test('toJson emits action keys', () {
      const region = GeofenceRegion(
        id: 'home',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
        action: GeofenceAction.notify,
        actionPayload: 'Hello',
        actionOn: GeofenceActionTrigger.exit,
      );
      final json = region.toJson();
      expect(json['action'], 'notify');
      expect(json['actionPayload'], 'Hello');
      expect(json['actionOn'], 'exit');
    });

    test('legacy JSON without action fields loads safe defaults', () {
      final legacy = GeofenceRegion.fromJson({
        'id': 'legacy',
        'name': 'Home',
        'latitude': 1.0,
        'longitude': 2.0,
        'radiusMeters': 100.0,
        'isEnabled': true,
      });
      expect(legacy.action, GeofenceAction.none);
      expect(legacy.actionPayload, isEmpty);
      expect(legacy.actionOn, GeofenceActionTrigger.both);
      expect(legacy.name, 'Home');
      expect(legacy.isEnabled, isTrue);
    });

    test('fromJson tolerates unknown and non-string action values', () {
      final unknownAction = GeofenceRegion.fromJson({
        'id': 'r1',
        'action': 'teleport',
      });
      expect(unknownAction.action, GeofenceAction.none);

      final unknownTrigger = GeofenceRegion.fromJson({
        'id': 'r2',
        'actionOn': 'whenever',
      });
      expect(unknownTrigger.actionOn, GeofenceActionTrigger.both);

      final badPayload = GeofenceRegion.fromJson({
        'id': 'r3',
        'action': 'openUrl',
        'actionPayload': 42,
      });
      expect(badPayload.action, GeofenceAction.openUrl);
      expect(badPayload.actionPayload, isEmpty);
    });

    test('fromJson supports action_type / action_payload / action_on keys', () {
      final region = GeofenceRegion.fromJson({
        'id': 'r1',
        'action_type': 'run_prompt',
        'action_payload': 'Turn on lights',
        'action_on': 'enter',
      });
      expect(region.action, GeofenceAction.runPrompt);
      expect(region.actionPayload, 'Turn on lights');
      expect(region.actionOn, GeofenceActionTrigger.enter);
    });

    test('copyWith updates action binding and preserves it when omitted', () {
      const region = GeofenceRegion(
        id: 'home',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
        action: GeofenceAction.notify,
        actionPayload: 'old',
        actionOn: GeofenceActionTrigger.enter,
      );
      final copy = region.copyWith(
        action: GeofenceAction.openUrl,
        actionPayload: 'https://example.com',
        actionOn: GeofenceActionTrigger.exit,
      );
      expect(copy.action, GeofenceAction.openUrl);
      expect(copy.actionPayload, 'https://example.com');
      expect(copy.actionOn, GeofenceActionTrigger.exit);
      expect(copy.id, 'home');

      final untouched = region.copyWith(name: 'House');
      expect(untouched.action, GeofenceAction.notify);
      expect(untouched.actionPayload, 'old');
      expect(untouched.actionOn, GeofenceActionTrigger.enter);
    });

    test('matchesEvent respects enter/exit/both triggers', () {
      const enterOnly = GeofenceRegion(
        id: 'a',
        latitude: 0.0,
        longitude: 0.0,
        radiusMeters: 100.0,
        actionOn: GeofenceActionTrigger.enter,
      );
      expect(enterOnly.matchesEvent(AmbientEventType.geofenceEnter), isTrue);
      expect(enterOnly.matchesEvent(AmbientEventType.geofenceExit), isFalse);

      const exitOnly = GeofenceRegion(
        id: 'b',
        latitude: 0.0,
        longitude: 0.0,
        radiusMeters: 100.0,
        actionOn: GeofenceActionTrigger.exit,
      );
      expect(exitOnly.matchesEvent(AmbientEventType.geofenceExit), isTrue);
      expect(exitOnly.matchesEvent(AmbientEventType.geofenceEnter), isFalse);

      const both = GeofenceRegion(
        id: 'c',
        latitude: 0.0,
        longitude: 0.0,
        radiusMeters: 100.0,
      );
      expect(both.matchesEvent(AmbientEventType.geofenceEnter), isTrue);
      expect(both.matchesEvent(AmbientEventType.geofenceExit), isTrue);

      expect(both.matchesEvent(AmbientEventType.batteryLow), isFalse);
      expect(both.matchesEvent(AmbientEventType.batteryCritical), isFalse);
    });

    test('geofenceActionFromJson accepts aliases case-insensitively', () {
      expect(geofenceActionFromJson('none'), GeofenceAction.none);
      expect(geofenceActionFromJson('notify'), GeofenceAction.notify);
      expect(geofenceActionFromJson('run_prompt'), GeofenceAction.runPrompt);
      expect(geofenceActionFromJson('RUNPROMPT'), GeofenceAction.runPrompt);
      expect(geofenceActionFromJson('prompt'), GeofenceAction.runPrompt);
      expect(geofenceActionFromJson('open_url'), GeofenceAction.openUrl);
      expect(geofenceActionFromJson('OpenURL'), GeofenceAction.openUrl);
      expect(geofenceActionFromJson('url'), GeofenceAction.openUrl);
      expect(geofenceActionFromJson(null), GeofenceAction.none);
      expect(geofenceActionFromJson(123), GeofenceAction.none);
    });

    test('geofenceActionTriggerFromJson accepts aliases case-insensitively', () {
      expect(geofenceActionTriggerFromJson('enter'), GeofenceActionTrigger.enter);
      expect(geofenceActionTriggerFromJson('EXIT'), GeofenceActionTrigger.exit);
      expect(geofenceActionTriggerFromJson('both'), GeofenceActionTrigger.both);
      expect(geofenceActionTriggerFromJson(null), GeofenceActionTrigger.both);
      expect(geofenceActionTriggerFromJson('nope'), GeofenceActionTrigger.both);
      expect(geofenceActionTriggerToJson(GeofenceActionTrigger.enter), 'enter');
      expect(geofenceActionTriggerToJson(GeofenceActionTrigger.exit), 'exit');
      expect(geofenceActionTriggerToJson(GeofenceActionTrigger.both), 'both');
    });

    test('label helpers return product vocabulary', () {
      expect(geofenceActionLabel(GeofenceAction.none), 'Nothing');
      expect(geofenceActionLabel(GeofenceAction.notify), 'Notify');
      expect(geofenceActionLabel(GeofenceAction.runPrompt), 'Send prompt');
      expect(geofenceActionLabel(GeofenceAction.openUrl), 'Open URL');
      expect(
        geofenceActionTriggerLabel(GeofenceActionTrigger.enter),
        'On enter',
      );
      expect(geofenceActionTriggerLabel(GeofenceActionTrigger.exit), 'On exit');
      expect(
        geofenceActionTriggerLabel(GeofenceActionTrigger.both),
        'On enter & exit',
      );
    });
  });

  group('geofence action validation', () {
    test('geofenceActionNames mirrors GeofenceAction.values', () {
      expect(
        geofenceActionNames,
        equals(GeofenceAction.values.map((a) => a.name).toList()),
      );
    });

    test('geofenceActionTryParse accepts canonical names', () {
      expect(geofenceActionTryParse('none'), GeofenceAction.none);
      expect(geofenceActionTryParse('notify'), GeofenceAction.notify);
      expect(geofenceActionTryParse('runPrompt'), GeofenceAction.runPrompt);
      expect(geofenceActionTryParse('openUrl'), GeofenceAction.openUrl);
    });

    test('geofenceActionTryParse trims and ignores case', () {
      expect(geofenceActionTryParse('  Notify  '), GeofenceAction.notify);
      expect(geofenceActionTryParse('RUNPROMPT'), GeofenceAction.runPrompt);
      expect(geofenceActionTryParse('openurl'), GeofenceAction.openUrl);
      expect(geofenceActionTryParse('NONE'), GeofenceAction.none);
    });

    test('geofenceActionTryParse rejects aliases and blanks', () {
      expect(geofenceActionTryParse('speak'), isNull);
      expect(geofenceActionTryParse('run_prompt'), isNull);
      expect(geofenceActionTryParse('url'), isNull);
      expect(geofenceActionTryParse('prompt'), isNull);
      expect(geofenceActionTryParse(''), isNull);
      expect(geofenceActionTryParse('   '), isNull);
      expect(geofenceActionTryParse(null), isNull);
    });

    test('geofenceActionBindingError allows payload-free actions', () {
      expect(
        geofenceActionBindingError(rawAction: 'none', actionPayload: ''),
        isNull,
      );
      expect(
        geofenceActionBindingError(rawAction: 'notify', actionPayload: ''),
        isNull,
      );
      expect(
        geofenceActionBindingError(rawAction: null, actionPayload: ''),
        isNull,
      );
      expect(
        geofenceActionBindingError(rawAction: '   ', actionPayload: ''),
        isNull,
      );
      expect(
        geofenceActionBindingError(rawAction: 'notify', actionPayload: 'x'),
        isNull,
      );
    });

    test('geofenceActionBindingError allows payload-bearing actions', () {
      expect(
        geofenceActionBindingError(
          rawAction: 'runPrompt',
          actionPayload: 'Start focus mode',
        ),
        isNull,
      );
      expect(
        geofenceActionBindingError(
          rawAction: 'openUrl',
          actionPayload: 'https://example.com',
        ),
        isNull,
      );
    });

    test('geofenceActionBindingError names offending value and allowed set', () {
      final message = geofenceActionBindingError(
        rawAction: 'speak',
        actionPayload: '',
      );
      expect(message, isNotNull);
      expect(message, contains('speak'));
      for (final name in geofenceActionNames) {
        expect(message, contains(name));
      }
    });

    test('geofenceActionBindingError requires payload for runPrompt', () {
      final message = geofenceActionBindingError(
        rawAction: 'runPrompt',
        actionPayload: '   ',
      );
      expect(message, isNotNull);
      expect(message, contains('runPrompt'));
      expect(message, contains('actionPayload'));
    });

    test('geofenceActionBindingError requires payload for openUrl', () {
      final message = geofenceActionBindingError(
        rawAction: 'openUrl',
        actionPayload: '',
      );
      expect(message, isNotNull);
      expect(message, contains('openUrl'));
      expect(message, contains('actionPayload'));
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
      expect(a.props.length, 4);
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

    test('defaults dispatchedActions to empty', () {
      final result = AmbientCheckResult(
        triggered: false,
        events: const [],
        checkedAt: fixedTime,
      );
      expect(result.dispatchedActions, isEmpty);
      expect(result.props.length, 4);
    });

    test('toJson omits dispatchedActions when empty', () {
      final result = AmbientCheckResult(
        triggered: false,
        events: const [],
        checkedAt: fixedTime,
      );
      expect(result.toJson().containsKey('dispatchedActions'), isFalse);
    });

    test('toJson / fromJson roundtrip preserves dispatchedActions', () {
      final result = AmbientCheckResult(
        triggered: true,
        events: const [],
        checkedAt: fixedTime,
        dispatchedActions: const [
          GeofenceDispatchResult(
            action: GeofenceAction.runPrompt,
            executed: true,
            payload: 'Lights on',
            transportId: 'chat',
            detail: 'prompt_dispatched',
          ),
          GeofenceDispatchResult(
            action: GeofenceAction.openUrl,
            executed: false,
            payload: 'https://example.com',
            detail: 'Cannot launch URL',
          ),
        ],
      );

      final json = result.toJson();
      expect(json['dispatchedActions'], hasLength(2));
      final restored = AmbientCheckResult.fromJson(json);
      expect(restored, equals(result));
      expect(restored.dispatchedActions.first.transportId, 'chat');
      expect(
        restored.dispatchedActions.first.detail,
        'prompt_dispatched',
      );
    });

    test('legacy JSON without dispatchedActions parses as empty', () {
      final legacy = AmbientCheckResult.fromJson({
        'triggered': true,
        'events': [],
        'checkedAt': fixedTime.toIso8601String(),
      });
      expect(legacy.dispatchedActions, isEmpty);
    });

    test('fromJson tolerates non-list and non-map dispatchedActions', () {
      final nonList = AmbientCheckResult.fromJson({
        'triggered': false,
        'events': [],
        'dispatchedActions': 'nope',
      });
      expect(nonList.dispatchedActions, isEmpty);

      final mixed = AmbientCheckResult.fromJson({
        'triggered': false,
        'events': [],
        'dispatchedActions': ['bad', 123, null],
      });
      expect(mixed.dispatchedActions, isEmpty);
    });
  });

  group('GeofenceDispatchResult', () {
    test('supports value equality and copyWith', () {
      const a = GeofenceDispatchResult(
        action: GeofenceAction.notify,
        executed: true,
        detail: 'notification',
      );
      const b = GeofenceDispatchResult(
        action: GeofenceAction.notify,
        executed: true,
        detail: 'notification',
      );
      expect(a, equals(b));
      expect(a.props.length, 5);
      expect(a.copyWith(), equals(a));

      final copy = a.copyWith(
        executed: false,
        detail: 'error',
        payload: 'x',
        transportId: 'chat',
      );
      expect(copy.executed, isFalse);
      expect(copy.detail, 'error');
      expect(copy.payload, 'x');
      expect(copy.transportId, 'chat');
    });

    test('toJson omits null transportId and detail', () {
      const result = GeofenceDispatchResult(
        action: GeofenceAction.none,
        executed: false,
        detail: 'none',
      );
      final json = result.toJson();
      expect(json['action'], 'none');
      expect(json['executed'], isFalse);
      expect(json['payload'], isEmpty);
      expect(json.containsKey('transportId'), isFalse);
      expect(json['detail'], 'none');

      const bare = GeofenceDispatchResult(
        action: GeofenceAction.none,
        executed: false,
      );
      expect(bare.toJson().containsKey('detail'), isFalse);
      expect(bare.toJson().containsKey('transportId'), isFalse);
    });

    test('fromJson roundtrips and defaults unknown action to none', () {
      const result = GeofenceDispatchResult(
        action: GeofenceAction.runPrompt,
        executed: true,
        payload: 'Lights on',
        transportId: 'chat',
        detail: 'prompt_dispatched',
      );
      expect(GeofenceDispatchResult.fromJson(result.toJson()), equals(result));

      final unknown = GeofenceDispatchResult.fromJson({
        'action': 'teleport',
        'executed': true,
      });
      expect(unknown.action, GeofenceAction.none);
      expect(unknown.executed, isTrue);
      expect(unknown.payload, isEmpty);
      expect(unknown.transportId, isNull);
      expect(unknown.detail, isNull);
    });
  });
}
