import 'dart:convert';

import 'package:flutter_ai_agent/data/datasources/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/mocks.dart';

void main() {
  late AmbientTriggerService service;
  late ToolRegistry registry;

  setUp(() {
    service = AmbientTriggerService(
      battery: MockBatteryPlatformWrapper(),
      workmanager: MockWorkmanagerPlatformWrapper(),
    );
    registry = ToolRegistry();
    registry.registerAmbientTriggerTools(service);
  });

  group('register_geofence acceptance round-trip', () {
    test('every allowed action survives register_geofence -> list_geofences',
        () async {
      // Arrange
      final payloads = <String, String>{
        'none': '',
        'notify': '',
        'runPrompt': 'Lights on',
        'openUrl': 'https://example.com',
      };

      // Act
      final registerResults = <String, bool>{};
      for (final name in geofenceActionNames) {
        final result = await registry.executeTool('register_geofence', {
          'id': 'rt_$name',
          'latitude': 1.0,
          'longitude': 2.0,
          'radiusMeters': 100.0,
          'action': name,
          'actionPayload': payloads[name],
          'actionOn': 'enter',
        });
        registerResults[name] = result.isRight();
      }

      final listResult = await registry.executeTool('list_geofences');
      final decoded = jsonDecode(listResult.getOrElse(() => '[]')) as List;
      final regions = decoded.cast<Map<String, dynamic>>();

      // Assert
      for (final name in geofenceActionNames) {
        expect(registerResults[name], isTrue, reason: 'register $name');
      }
      expect(regions, hasLength(geofenceActionNames.length));
      for (final name in geofenceActionNames) {
        final entry = regions.firstWhere((r) => r['id'] == 'rt_$name');
        expect(entry['action'], name, reason: 'action survived for $name');
        expect(entry['actionPayload'], payloads[name]);
        expect(entry['actionOn'], 'enter');
      }
      expect(
        regions.map((r) => r['action']).toSet(),
        equals(geofenceActionNames.toSet()),
      );
    });

    test('an unknown action never reaches the registry', () async {
      // Arrange / Act
      final result = await registry.executeTool('register_geofence', {
        'id': 'rt_bad',
        'latitude': 1.0,
        'longitude': 2.0,
        'radiusMeters': 100.0,
        'action': 'speak',
        'actionPayload': 'hi',
      });

      // Assert
      expect(result.isLeft(), isTrue);
      expect(
        result.fold((failure) => failure.message, (_) => ''),
        contains('speak'),
      );
      final listResult = await registry.executeTool('list_geofences');
      expect(jsonDecode(listResult.getOrElse(() => '[]')), isEmpty);
    });

    test('a payload-taking action without a payload never reaches the registry',
        () async {
      // Arrange / Act
      final result = await registry.executeTool('register_geofence', {
        'id': 'rt_empty',
        'latitude': 1.0,
        'longitude': 2.0,
        'radiusMeters': 100.0,
        'action': 'runPrompt',
      });

      // Assert
      expect(result.isLeft(), isTrue);
      final listResult = await registry.executeTool('list_geofences');
      expect(jsonDecode(listResult.getOrElse(() => '[]')), isEmpty);
    });
  });
}
