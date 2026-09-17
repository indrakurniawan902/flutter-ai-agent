import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/presentation/screen/node/cubit/geofence_management_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockSecureStorageService mockStorage;
  late MockAmbientTriggerService mockAmbient;
  late MockLocationService mockLocation;

  setUpAll(() {
    registerFallbackValue(const GeofenceRegion(
      id: '',
      name: '',
      latitude: 0,
      longitude: 0,
      radiusMeters: 0,
    ));
    registerFallbackValue(<GeofenceRegion>[]);
  });

  setUp(() {
    mockStorage = MockSecureStorageService();
    mockAmbient = MockAmbientTriggerService();
    mockLocation = MockLocationService();
  });

  Future<GeofenceManagementCubit> seedCubit(
    List<GeofenceRegion> regions,
  ) async {
    when(() => mockStorage.getGeofences()).thenAnswer((_) async => regions);
    when(() => mockStorage.saveGeofences(any())).thenAnswer((_) async {});
    when(() => mockAmbient.regions).thenAnswer((_) => regions);

    final cubit = GeofenceManagementCubit(
      storage: mockStorage,
      ambient: mockAmbient,
      location: mockLocation,
    );
    await cubit.load();
    clearInteractions(mockStorage);
    clearInteractions(mockAmbient);
    return cubit;
  }

  GeofenceRegion region({
    String id = 'gf-1',
    String name = 'Home',
    double latitude = 12.5,
    double longitude = -45.25,
    double radiusMeters = 100,
    bool isEnabled = true,
  }) {
    return GeofenceRegion(
      id: id,
      name: name,
      latitude: latitude,
      longitude: longitude,
      radiusMeters: radiusMeters,
      isEnabled: isEnabled,
    );
  }

  group('GeofenceManagementCubit.updateGeofence', () {
    test('persists the change with the SAME id as the original region',
        () async {
      // Arrange
      final original = region(id: 'gf-original');
      final cubit = await seedCubit([original]);

      // Act
      final result = await cubit.updateGeofence(
        'gf-original',
        label: 'Home Updated',
        latitude: 3.0,
        longitude: 4.0,
        radiusMeters: 200,
      );

      // Assert
      expect(result, isTrue);
      final captured =
          verify(() => mockStorage.saveGeofences(captureAny())).captured;
      final saved = captured.single as List<GeofenceRegion>;
      expect(saved.single.id, original.id);
      expect(saved.single.name, 'Home Updated');
      expect(cubit.state.regions.single.id, original.id);
    });

    test('preserves isEnabled false from the existing region', () async {
      // Arrange
      final original = region(id: 'gf-disabled', isEnabled: false);
      final cubit = await seedCubit([original]);

      // Act
      final result = await cubit.updateGeofence(
        'gf-disabled',
        label: 'Still Off',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 300,
      );

      // Assert
      expect(result, isTrue);
      final captured =
          verify(() => mockStorage.saveGeofences(captureAny())).captured;
      final saved = captured.single as List<GeofenceRegion>;
      expect(saved.single.isEnabled, isFalse);
      expect(cubit.state.regions.single.isEnabled, isFalse);
    });

    test('updates the live engine once with the updated region', () async {
      // Arrange
      final original = region();
      final cubit = await seedCubit([original]);
      final expected = original.copyWith(
        name: 'Office',
        latitude: 3.0,
        longitude: 4.0,
        radiusMeters: 200,
      );

      // Act
      final result = await cubit.updateGeofence(
        original.id,
        label: 'Office',
        latitude: 3.0,
        longitude: 4.0,
        radiusMeters: 200,
      );

      // Assert
      expect(result, isTrue);
      verify(() => mockAmbient.addGeofence(expected)).called(1);
      expect(cubit.state.regions, [expected]);
    });

    test('keeps list order when several regions exist', () async {
      // Arrange
      final first = region(id: 'gf-a', name: 'A');
      final second = region(id: 'gf-b', name: 'B');
      final third = region(id: 'gf-c', name: 'C');
      final cubit = await seedCubit([first, second, third]);

      // Act
      final result = await cubit.updateGeofence(
        'gf-b',
        label: 'B Updated',
        latitude: 5.0,
        longitude: 6.0,
        radiusMeters: 400,
      );

      // Assert
      expect(result, isTrue);
      expect(cubit.state.regions.map((r) => r.id), ['gf-a', 'gf-b', 'gf-c']);
      final captured =
          verify(() => mockStorage.saveGeofences(captureAny())).captured;
      final saved = captured.single as List<GeofenceRegion>;
      expect(saved.map((r) => r.id), ['gf-a', 'gf-b', 'gf-c']);
      expect(saved[1].name, 'B Updated');
    });

    test('unknown id returns false, emits error and never persists', () async {
      // Arrange
      final cubit = await seedCubit([region()]);

      // Act
      final result = await cubit.updateGeofence(
        'missing-id',
        label: 'Ghost',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100,
      );

      // Assert
      expect(result, isFalse);
      expect(cubit.state.error, 'Geofence not found');
      verifyNever(() => mockStorage.saveGeofences(any()));
      verifyNever(() => mockAmbient.addGeofence(any()));
    });

    test('rejects invalid input without persisting or touching the engine',
        () async {
      final invalidCases =
          <String, ({String label, double lat, double lng, double radius})>{
        'latitude above 90': (label: 'Home', lat: 91, lng: 0, radius: 100),
        'longitude above 180': (label: 'Home', lat: 0, lng: 181, radius: 100),
        'radius zero': (label: 'Home', lat: 0, lng: 0, radius: 0),
        'empty label': (label: '   ', lat: 0, lng: 0, radius: 100),
      };

      for (final entry in invalidCases.entries) {
        // Arrange
        final cubit = await seedCubit([region()]);

        // Act
        final result = await cubit.updateGeofence(
          'gf-1',
          label: entry.value.label,
          latitude: entry.value.lat,
          longitude: entry.value.lng,
          radiusMeters: entry.value.radius,
        );

        // Assert
        expect(result, isFalse, reason: entry.key);
        expect(cubit.state.error, isNotNull, reason: entry.key);
        verifyNever(() => mockStorage.saveGeofences(any()));
        verifyNever(() => mockAmbient.addGeofence(any()));
      }
    });

    test('updating only the radius keeps latitude and longitude unchanged',
        () async {
      // Arrange
      final original = region(latitude: 12.5, longitude: -45.25);
      final cubit = await seedCubit([original]);

      // Act
      final result = await cubit.updateGeofence(
        original.id,
        label: 'Home',
        latitude: original.latitude,
        longitude: original.longitude,
        radiusMeters: 500,
      );

      // Assert
      expect(result, isTrue);
      final captured =
          verify(() => mockStorage.saveGeofences(captureAny())).captured;
      final saved = captured.single as List<GeofenceRegion>;
      expect(saved.single.radiusMeters, 500);
      expect(saved.single.latitude, 12.5);
      expect(saved.single.longitude, -45.25);
    });
  });

  group('GeofenceManagementCubit.addGeofence', () {
    test('rejects invalid input without persisting', () async {
      final invalidCases =
          <String, ({String label, double lat, double lng, double radius})>{
        'latitude above 90': (label: 'Home', lat: 91, lng: 0, radius: 100),
        'longitude above 180': (label: 'Home', lat: 0, lng: 181, radius: 100),
        'radius zero': (label: 'Home', lat: 0, lng: 0, radius: 0),
        'empty label': (label: '   ', lat: 0, lng: 0, radius: 100),
      };

      for (final entry in invalidCases.entries) {
        // Arrange
        final cubit = await seedCubit(const []);

        // Act
        final result = await cubit.addGeofence(
          label: entry.value.label,
          latitude: entry.value.lat,
          longitude: entry.value.lng,
          radiusMeters: entry.value.radius,
        );

        // Assert
        expect(result, isNull, reason: entry.key);
        expect(cubit.state.error, isNotNull, reason: entry.key);
        expect(cubit.state.regions, isEmpty, reason: entry.key);
        verifyNever(() => mockStorage.saveGeofences(any()));
        verifyNever(() => mockAmbient.addGeofence(any()));
      }
    });
  });

  group('GeofenceManagementCubit.addGeofence action binding', () {
    List<GeofenceRegion> capturedSaved() {
      final captured =
          verify(() => mockStorage.saveGeofences(captureAny())).captured;
      return captured.last as List<GeofenceRegion>;
    }

    test('persists and registers the region with the bound action', () async {
      // Arrange
      final cubit = await seedCubit(const []);

      // Act
      final id = await cubit.addGeofence(
        label: 'Work',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
        action: GeofenceAction.runPrompt,
        actionPayload: 'Start focus mode',
        actionOn: GeofenceActionTrigger.enter,
      );

      // Assert
      expect(id, isNotNull);
      final saved = capturedSaved();
      expect(saved, hasLength(1));
      expect(saved.first.id, id);
      expect(saved.first.action, GeofenceAction.runPrompt);
      expect(saved.first.actionPayload, 'Start focus mode');
      expect(saved.first.actionOn, GeofenceActionTrigger.enter);
      verify(() => mockAmbient.addGeofence(saved.first)).called(1);
    });

    test('defaults to no action when none is provided', () async {
      // Arrange
      final cubit = await seedCubit(const []);

      // Act
      await cubit.addGeofence(
        label: 'Home',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
      );

      // Assert
      final saved = capturedSaved();
      expect(saved.first.action, GeofenceAction.none);
      expect(saved.first.actionPayload, isEmpty);
      expect(saved.first.actionOn, GeofenceActionTrigger.both);
    });

    test('returned id matches the persisted region id', () async {
      // Arrange
      final cubit = await seedCubit(const []);

      // Act
      final id = await cubit.addGeofence(
        label: 'Gym',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
      );

      // Assert
      expect(id, isNotNull);
      expect(capturedSaved().first.id, id);
    });

    test('storage failure returns null and does not touch the engine',
        () async {
      // Arrange
      final cubit = await seedCubit(const []);
      when(() => mockStorage.saveGeofences(any()))
          .thenThrow(Exception('disk full'));

      // Act
      final id = await cubit.addGeofence(
        label: 'Home',
        latitude: 1.0,
        longitude: 2.0,
        radiusMeters: 100.0,
      );

      // Assert
      expect(id, isNull);
      verifyNever(() => mockAmbient.addGeofence(any()));
      expect(cubit.state.regions, isEmpty);
    });
  });
}
