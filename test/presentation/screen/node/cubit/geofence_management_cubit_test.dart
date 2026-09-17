import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/presentation/screen/node/cubit/geofence_management_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockSecureStorageService mockStorage;
  late MockAmbientTriggerService mockAmbient;
  late MockLocationService mockLocation;
  late GeofenceManagementCubit cubit;

  setUpAll(() {
    registerFallbackValue(
      const GeofenceRegion(
        id: 'fallback',
        latitude: 0.0,
        longitude: 0.0,
        radiusMeters: 100.0,
      ),
    );
    registerFallbackValue(<GeofenceRegion>[]);
  });

  setUp(() {
    mockStorage = MockSecureStorageService();
    mockAmbient = MockAmbientTriggerService();
    mockLocation = MockLocationService();
    when(() => mockStorage.getGeofences())
        .thenAnswer((_) async => const <GeofenceRegion>[]);
    when(() => mockStorage.saveGeofences(any())).thenAnswer((_) async {});
    when(() => mockAmbient.regions).thenAnswer((_) => const []);
    cubit = GeofenceManagementCubit(
      storage: mockStorage,
      ambient: mockAmbient,
      location: mockLocation,
    );
  });

  tearDown(() async {
    await cubit.close();
  });

  List<GeofenceRegion> capturedSaved() {
    final captured =
        verify(() => mockStorage.saveGeofences(captureAny())).captured;
    return captured.last as List<GeofenceRegion>;
  }

  group('addGeofence action binding', () {
    test('persists and registers the region with the bound action', () async {
      // Arrange + Act
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
      // Arrange + Act
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
      // Arrange + Act
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
