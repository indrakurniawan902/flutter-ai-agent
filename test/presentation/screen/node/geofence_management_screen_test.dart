import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/app_settings_opener.dart';
import 'package:flutter_ai_agent/presentation/screen/node/geofence_management_screen.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/utils/permission_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../helpers/mocks.dart';

class _MockPermissionRequester extends Mock implements PermissionRequester {}

class _FakeAppSettingsOpener implements AppSettingsOpener {
  int calls = 0;

  @override
  Future<bool> openAppSettings() async {
    calls++;
    return true;
  }
}

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
    registerFallbackValue(Permission.location);
  });

  setUp(() async {
    await sl.reset();
  });

  tearDown(() async {
    await sl.reset();
  });

  Widget createWidgetUnderTest({PermissionGate? gate}) {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: GeofenceManagementScreen(permissionGate: gate),
    );
  }

  PermissionGate gateWith(PermissionStatus status, {AppSettingsOpener? opener}) {
    final requester = _MockPermissionRequester();
    when(() => requester.checkStatus(any())).thenAnswer((_) async => status);
    when(() => requester.requestPermission(any())).thenAnswer((_) async => status);
    return PermissionGate(requester: requester, settingsOpener: opener);
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

      await tester.pumpWidget(
        createWidgetUnderTest(gate: gateWith(PermissionStatus.granted)),
      );
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

    testWidgets('double tap on Add Geofence creates only one geofence',
        (tester) async {
      final mockStorage = MockSecureStorageService();
      final mockAmbient = MockAmbientTriggerService();
      final mockLocation = MockLocationService();
      final saveCompleter = Completer<void>();

      when(() => mockStorage.getGeofences())
          .thenAnswer((_) async => const <GeofenceRegion>[]);
      when(() => mockStorage.saveGeofences(any()))
          .thenAnswer((invocation) async {
        final list =
            invocation.positionalArguments.first as List<GeofenceRegion>;
        if (list.isNotEmpty) await saveCompleter.future;
      });
      when(() => mockAmbient.regions).thenAnswer((_) => const []);
      when(() => mockLocation.getLocation()).thenAnswer(
        (_) async => Right(<String, dynamic>{'latitude': 0, 'longitude': 0}),
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
      await tester.pump();
      await tester.tap(find.byKey(const Key('geofence_submit')));
      await tester.pump();

      saveCompleter.complete();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('geofence_empty')), findsNothing);
      final captured = verify(
        () => mockStorage.saveGeofences(captureAny()),
      ).captured.whereType<List<GeofenceRegion>>().where((l) => l.isNotEmpty);
      expect(captured.length, 1);
      expect(captured.first.length, 1);
    });

    testWidgets('persist failure surfaces an error and keeps the form values',
        (tester) async {
      final mockStorage = MockSecureStorageService();
      final mockAmbient = MockAmbientTriggerService();
      final mockLocation = MockLocationService();

      when(() => mockStorage.getGeofences())
          .thenAnswer((_) async => const <GeofenceRegion>[]);
      when(() => mockStorage.saveGeofences(any()))
          .thenAnswer((invocation) async {
        final list =
            invocation.positionalArguments.first as List<GeofenceRegion>;
        if (list.isNotEmpty) throw Exception('disk full');
      });
      when(() => mockAmbient.regions).thenAnswer((_) => const []);
      when(() => mockLocation.getLocation()).thenAnswer(
        (_) async => Right(<String, dynamic>{'latitude': 0, 'longitude': 0}),
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

      expect(find.textContaining('disk full'), findsOneWidget);
      expect(find.byKey(const Key('geofence_empty')), findsOneWidget);
      final labelField = tester.widget<TextFormField>(
        find.byKey(const Key('geofence_label_field')),
      );
      expect(labelField.controller?.text, 'Office');
    });

    testWidgets(
        'use current location when permission granted fills lat and lng',
        (tester) async {
      registerMocks();
      final gate = gateWith(PermissionStatus.granted);

      await tester.pumpWidget(createWidgetUnderTest(gate: gate));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('geofence_use_current_location')));
      await tester.pumpAndSettle();

      expect(find.text('37.774900'), findsOneWidget);
      expect(find.text('-122.419400'), findsOneWidget);
    });

    testWidgets(
        'use current location when permission denied shows rationale and '
        'captures nothing', (tester) async {
      registerMocks();
      final mockLocation = sl<LocationServiceBase>();
      final gate = gateWith(PermissionStatus.denied);

      await tester.pumpWidget(createWidgetUnderTest(gate: gate));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('geofence_use_current_location')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const Key('permission_rationale_allow_btn')),
        findsOneWidget,
      );
      verifyNever(() => mockLocation.getLocation());
      expect(find.text('37.774900'), findsNothing);
    });

    testWidgets(
        'use current location when permission permanently denied offers '
        'Buka Pengaturan', (tester) async {
      registerMocks();
      final mockLocation = sl<LocationServiceBase>();
      final opener = _FakeAppSettingsOpener();
      final gate =
          gateWith(PermissionStatus.permanentlyDenied, opener: opener);

      await tester.pumpWidget(createWidgetUnderTest(gate: gate));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('geofence_use_current_location')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const Key('permission_rationale_permanently_denied_notice')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('permission_rationale_allow_btn')),
      );
      await tester.pumpAndSettle();

      expect(opener.calls, 1);
      verifyNever(() => mockLocation.getLocation());
    });

    testWidgets('selected radius is used when saving', (tester) async {
      final mockStorage = MockSecureStorageService();
      final mockAmbient = MockAmbientTriggerService();
      final mockLocation = MockLocationService();

      when(() => mockStorage.getGeofences())
          .thenAnswer((_) async => const <GeofenceRegion>[]);
      when(() => mockStorage.saveGeofences(any())).thenAnswer((_) async {});
      when(() => mockAmbient.regions).thenAnswer((_) => const []);
      when(() => mockLocation.getLocation()).thenAnswer(
        (_) async => Right(<String, dynamic>{'latitude': 0, 'longitude': 0}),
      );

      sl.registerSingleton<SecureStorageService>(mockStorage);
      sl.registerSingleton<AmbientTriggerServiceBase>(mockAmbient);
      sl.registerSingleton<LocationServiceBase>(mockLocation);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('geofence_radius_dropdown')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('200 m').last);
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('geofence_label_field')), 'Office');
      await tester.enterText(
          find.byKey(const Key('geofence_lat_field')), '40.7128');
      await tester.enterText(
          find.byKey(const Key('geofence_lng_field')), '-74.0060');

      await tester.tap(find.byKey(const Key('geofence_submit')));
      await tester.pumpAndSettle();

      final captured =
          verify(() => mockStorage.saveGeofences(captureAny())).captured;
      final saved = captured.last as List<GeofenceRegion>;
      expect(saved.length, 1);
      expect(saved.first.radiusMeters, 200);
    });

    testWidgets('each row shows an edit action', (tester) async {
      final regions = [
        GeofenceRegion(
          id: 'gf1',
          name: 'Home',
          latitude: 0,
          longitude: 0,
          radiusMeters: 100,
        ),
        GeofenceRegion(
          id: 'gf2',
          name: 'Work',
          latitude: 1,
          longitude: 1,
          radiusMeters: 200,
        ),
      ];
      registerMocks(initialRegions: regions);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('geofence_edit_gf1')), findsOneWidget);
      expect(find.byKey(const Key('geofence_edit_gf2')), findsOneWidget);
    });

    testWidgets('tapping edit opens the sheet prefilled', (tester) async {
      final regions = [
        GeofenceRegion(
          id: 'gf1',
          name: 'Home',
          latitude: 37.7749,
          longitude: -122.4194,
          radiusMeters: 100,
        ),
      ];
      registerMocks(initialRegions: regions);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('geofence_edit_gf1')));
      await tester.pumpAndSettle();

      expect(find.text('Edit Geofence'), findsOneWidget);
      expect(find.text('Save Changes'), findsOneWidget);

      final sheet = find.byType(BottomSheet);
      final labelField = tester.widget<TextFormField>(
        find.descendant(
          of: sheet,
          matching: find.byKey(const Key('geofence_label_field')),
        ),
      );
      final latField = tester.widget<TextFormField>(
        find.descendant(
          of: sheet,
          matching: find.byKey(const Key('geofence_lat_field')),
        ),
      );
      final lngField = tester.widget<TextFormField>(
        find.descendant(
          of: sheet,
          matching: find.byKey(const Key('geofence_lng_field')),
        ),
      );

      expect(labelField.controller?.text, 'Home');
      expect(latField.controller?.text, '37.774900');
      expect(lngField.controller?.text, '-122.419400');
    });

    testWidgets('editing the radius persists with the same id and one region',
        (tester) async {
      final regions = [
        GeofenceRegion(
          id: 'gf1',
          name: 'Home',
          latitude: 12.5,
          longitude: -45.25,
          radiusMeters: 100,
        ),
      ];
      final mockStorage = MockSecureStorageService();
      final mockAmbient = MockAmbientTriggerService();
      final mockLocation = MockLocationService();

      when(() => mockStorage.getGeofences())
          .thenAnswer((_) async => regions);
      when(() => mockStorage.saveGeofences(any())).thenAnswer((_) async {});
      when(() => mockAmbient.regions).thenAnswer((_) => regions);
      when(() => mockLocation.getLocation()).thenAnswer(
        (_) async => Right(<String, dynamic>{'latitude': 0, 'longitude': 0}),
      );

      sl.registerSingleton<SecureStorageService>(mockStorage);
      sl.registerSingleton<AmbientTriggerServiceBase>(mockAmbient);
      sl.registerSingleton<LocationServiceBase>(mockLocation);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('geofence_edit_gf1')));
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      await tester.tap(
        find.descendant(
          of: sheet,
          matching: find.byKey(const Key('geofence_radius_dropdown')),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('200 m').last);
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: sheet,
          matching: find.byKey(const Key('geofence_submit')),
        ),
      );
      await tester.pumpAndSettle();

      final captured =
          verify(() => mockStorage.saveGeofences(captureAny())).captured;
      final saved = captured.last as List<GeofenceRegion>;
      expect(saved.length, 1);
      expect(saved.single.id, 'gf1');
      expect(saved.single.radiusMeters, 200);
      expect(saved.single.latitude, 12.5);
      expect(saved.single.longitude, -45.25);
    });

    testWidgets('invalid edit shows a validation message and never persists',
        (tester) async {
      final regions = [
        GeofenceRegion(
          id: 'gf1',
          name: 'Home',
          latitude: 12.5,
          longitude: -45.25,
          radiusMeters: 100,
        ),
      ];
      final mockStorage = MockSecureStorageService();
      final mockAmbient = MockAmbientTriggerService();
      final mockLocation = MockLocationService();

      when(() => mockStorage.getGeofences())
          .thenAnswer((_) async => regions);
      when(() => mockStorage.saveGeofences(any())).thenAnswer((_) async {});
      when(() => mockAmbient.regions).thenAnswer((_) => regions);
      when(() => mockLocation.getLocation()).thenAnswer(
        (_) async => Right(<String, dynamic>{'latitude': 0, 'longitude': 0}),
      );

      sl.registerSingleton<SecureStorageService>(mockStorage);
      sl.registerSingleton<AmbientTriggerServiceBase>(mockAmbient);
      sl.registerSingleton<LocationServiceBase>(mockLocation);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('geofence_edit_gf1')));
      await tester.pumpAndSettle();

      // `load()` persists the merged list once; only the edit path is under
      // test here, so reset the recorded interactions before acting.
      clearInteractions(mockStorage);
      clearInteractions(mockAmbient);

      final sheet = find.byType(BottomSheet);
      await tester.enterText(
        find.descendant(
          of: sheet,
          matching: find.byKey(const Key('geofence_lat_field')),
        ),
        '91',
      );
      await tester.tap(
        find.descendant(
          of: sheet,
          matching: find.byKey(const Key('geofence_submit')),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Latitude must be between -90 and 90'), findsOneWidget);
      verifyNever(() => mockStorage.saveGeofences(any()));
      verifyNever(() => mockAmbient.addGeofence(any()));
    });

    testWidgets('add form still creates a new region after the generalisation',
        (tester) async {
      final mockStorage = MockSecureStorageService();
      final mockAmbient = MockAmbientTriggerService();
      final mockLocation = MockLocationService();

      when(() => mockStorage.getGeofences())
          .thenAnswer((_) async => const <GeofenceRegion>[]);
      when(() => mockStorage.saveGeofences(any())).thenAnswer((_) async {});
      when(() => mockAmbient.regions).thenAnswer((_) => const []);
      when(() => mockLocation.getLocation()).thenAnswer(
        (_) async => Right(<String, dynamic>{'latitude': 0, 'longitude': 0}),
      );

      sl.registerSingleton<SecureStorageService>(mockStorage);
      sl.registerSingleton<AmbientTriggerServiceBase>(mockAmbient);
      sl.registerSingleton<LocationServiceBase>(mockLocation);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Add Geofence'), findsWidgets);
      expect(find.text('Edit Geofence'), findsNothing);

      await tester.enterText(
          find.byKey(const Key('geofence_label_field')), 'Cabin');
      await tester.enterText(
          find.byKey(const Key('geofence_lat_field')), '10.0');
      await tester.enterText(
          find.byKey(const Key('geofence_lng_field')), '20.0');

      await tester.tap(find.byKey(const Key('geofence_submit')));
      await tester.pumpAndSettle();

      expect(find.text('Cabin'), findsOneWidget);
      final captured =
          verify(() => mockStorage.saveGeofences(captureAny())).captured;
      final saved = captured.last as List<GeofenceRegion>;
      expect(saved.length, 1);
      expect(saved.single.name, 'Cabin');
    });
  });
}
