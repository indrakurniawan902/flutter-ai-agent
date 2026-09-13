import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/presentation/screen/node/geofence_management_screen.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  setUpAll(() {
    registerFallbackValue(const GeofenceRegion(
      id: '',
      name: '',
      latitude: 0.0,
      longitude: 0.0,
      radiusMeters: 0.0,
    ));
    registerFallbackValue(<GeofenceRegion>[]);
  });

  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
    await sl.reset();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: const GeofenceManagementScreen(),
    );
  }

  void registerMocks({
    List<GeofenceRegion> initialRegions = const [],
  }) {
    final mockStorage = MockSecureStorageService();
    final mockAmbient = MockAmbientTriggerService();
    final mockLocation = MockLocationService();

    when(() => mockStorage.getGeofences())
        .thenAnswer((_) async => initialRegions);
    when(() => mockStorage.saveGeofences(any()))
        .thenAnswer((_) async {});
    when(() => mockAmbient.regions).thenAnswer((_) => initialRegions);
    when(() => mockLocation.getLocation()).thenAnswer(
      (_) async => Right(<String, dynamic>{
        'latitude': 37.7749,
        'longitude': -122.4194,
      }),
    );

    sl.registerSingleton<SecureStorageService>(mockStorage);
    sl.registerSingleton<AmbientTriggerServiceBase>(mockAmbient);
    sl.registerSingleton<LocationServiceBase>(mockLocation);
  }

  group('GeofenceManagementScreen', () {
    testWidgets('renders empty state when no geofences', (tester) async {
      registerMocks();

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Manage Geofences'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byKey(const Key('geofence_empty')), findsOneWidget);
      expect(find.text('No geofences yet'), findsOneWidget);
    });

    testWidgets('renders list of geofences with name, lat, lng, radius',
        (tester) async {
      final regions = [
        GeofenceRegion(
          id: 'gf1',
          name: 'Home',
          latitude: 37.7749,
          longitude: -122.4194,
          radiusMeters: 100,
          isEnabled: true,
        ),
        GeofenceRegion(
          id: 'gf2',
          name: 'Work',
          latitude: 34.0522,
          longitude: -118.2437,
          radiusMeters: 200,
          isEnabled: false,
        ),
      ];

      registerMocks(initialRegions: regions);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Work'), findsOneWidget);
      expect(find.text('37.77490, -122.41940 • 100 m'), findsOneWidget);
      expect(find.text('34.05220, -118.24370 • 200 m'), findsOneWidget);
      expect(find.byKey(const Key('geofence_switch_gf1')), findsOneWidget);
      expect(find.byKey(const Key('geofence_switch_gf2')), findsOneWidget);
      expect(find.byKey(const Key('geofence_delete_gf1')), findsOneWidget);
      expect(find.byKey(const Key('geofence_delete_gf2')), findsOneWidget);
    });

    testWidgets('renders add-geofence form with all inputs',
        (tester) async {
      registerMocks();

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('geofence_label_field')), findsOneWidget);
      expect(find.byKey(const Key('geofence_lat_field')), findsOneWidget);
      expect(find.byKey(const Key('geofence_lng_field')), findsOneWidget);
      expect(find.byKey(const Key('geofence_use_current_location')),
          findsOneWidget);
      expect(find.byKey(const Key('geofence_radius_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('geofence_submit')), findsOneWidget);
    });

    testWidgets('tapping switch calls toggleGeofence on ambient service',
        (tester) async {
      final regions = [
        GeofenceRegion(
          id: 'gf1',
          name: 'Home',
          latitude: 0,
          longitude: 0,
          radiusMeters: 100,
          isEnabled: true,
        ),
      ];
      registerMocks(initialRegions: regions);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('geofence_switch_gf1')));
      await tester.pumpAndSettle();

      final ambient = sl<AmbientTriggerServiceBase>();
      verify(() => ambient.toggleGeofence('gf1', false)).called(1);
    });

    testWidgets('delete with confirmation removes geofence',
        (tester) async {
      final regions = [
        GeofenceRegion(
          id: 'gf1',
          name: 'Home',
          latitude: 0,
          longitude: 0,
          radiusMeters: 100,
          isEnabled: true,
        ),
      ];
      registerMocks(initialRegions: regions);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('geofence_delete_gf1')));
      await tester.pumpAndSettle();

      expect(find.text('Delete geofence?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('geofence_delete_confirm')));
      await tester.pumpAndSettle();

      final ambient = sl<AmbientTriggerServiceBase>();
      verify(() => ambient.removeGeofence('gf1')).called(1);
      expect(find.text('Home'), findsNothing);
    });

    testWidgets('use current location fills lat/lng fields',
        (tester) async {
      registerMocks();

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('geofence_use_current_location')));
      await tester.pumpAndSettle();

      expect(find.text('37.774900'), findsOneWidget);
      expect(find.text('-122.419400'), findsOneWidget);
    });

    testWidgets('submitting form saves new geofence', (tester) async {
      final mockStorage = MockSecureStorageService();
      final mockAmbient = MockAmbientTriggerService();
      final mockLocation = MockLocationService();

      when(() => mockStorage.getGeofences())
          .thenAnswer((_) async => const <GeofenceRegion>[]);
      when(() => mockStorage.saveGeofences(any()))
          .thenAnswer((_) async {});
      when(() => mockAmbient.regions).thenAnswer((_) => const []);
      when(() => mockLocation.getLocation()).thenAnswer(
        (_) async => Right(<String, dynamic>{
          'latitude': 0,
          'longitude': 0,
        }),
      );

      sl.registerSingleton<SecureStorageService>(mockStorage);
      sl.registerSingleton<AmbientTriggerServiceBase>(mockAmbient);
      sl.registerSingleton<LocationServiceBase>(mockLocation);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('geofence_label_field')), 'Office');
      await tester.enterText(
          find.byKey(const Key('geofence_lat_field')), '40.7128');
      await tester.enterText(
          find.byKey(const Key('geofence_lng_field')), '-74.0060');

      await tester.tap(find.byKey(const Key('geofence_submit')));
      await tester.pumpAndSettle();

      expect(find.text('Office'), findsOneWidget);
      final captured =
          verify(() => mockStorage.saveGeofences(captureAny())).captured;
      final saved = (captured.last as List<GeofenceRegion>);
      expect(saved.length, 1);
      expect(saved.first.name, 'Office');
    });

    testWidgets('load merges engine-only tool-registered geofence without '
        'clobbering', (tester) async {
      final storageRegion = GeofenceRegion(
        id: 'gf-storage',
        name: 'From Storage',
        latitude: 1,
        longitude: 2,
        radiusMeters: 50,
        isEnabled: true,
      );
      final toolRegion = GeofenceRegion(
        id: 'gf-tool',
        name: 'From LLM',
        latitude: 3,
        longitude: 4,
        radiusMeters: 100,
        isEnabled: true,
      );

      final mockStorage = MockSecureStorageService();
      final mockAmbient = MockAmbientTriggerService();
      final mockLocation = MockLocationService();

      when(() => mockStorage.getGeofences())
          .thenAnswer((_) async => [storageRegion]);
      when(() => mockStorage.saveGeofences(any())).thenAnswer((_) async {});
      when(() => mockAmbient.regions).thenAnswer((_) => [toolRegion]);
      when(() => mockLocation.getLocation()).thenAnswer(
        (_) async => Right(<String, dynamic>{
          'latitude': 0,
          'longitude': 0,
        }),
      );

      sl.registerSingleton<SecureStorageService>(mockStorage);
      sl.registerSingleton<AmbientTriggerServiceBase>(mockAmbient);
      sl.registerSingleton<LocationServiceBase>(mockLocation);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('From Storage'), findsOneWidget);
      expect(find.text('From LLM'), findsOneWidget);

      verifyNever(() => mockAmbient.clearGeofences());
      verifyNever(() => mockAmbient.removeGeofence(any()));
      verify(() => mockAmbient.addGeofence(storageRegion)).called(1);

      final captured =
          verify(() => mockStorage.saveGeofences(captureAny())).captured;
      final saved = captured.last as List<GeofenceRegion>;
      expect(saved.map((r) => r.id), containsAll(['gf-storage', 'gf-tool']));
    });
  });
}
