import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

class MockGeolocatorWrapper extends Mock implements GeolocatorPlatformWrapper {}

class MockGeocodingWrapper extends Mock implements GeocodingPlatformWrapper {}

Position fakePosition({double lat = 1.0, double lng = 2.0}) {
  return Position(
    latitude: lat,
    longitude: lng,
    timestamp: DateTime.fromMillisecondsSinceEpoch(0).toUtc(),
    accuracy: 0,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

void main() {
  late MockGeolocatorWrapper mockGeolocator;
  late MockGeocodingWrapper mockGeocoding;
  late LocationService service;

  setUp(() {
    mockGeolocator = MockGeolocatorWrapper();
    mockGeocoding = MockGeocodingWrapper();
    service = LocationService(
      geolocator: mockGeolocator,
      geocoding: mockGeocoding,
    );
  });

  setUpAll(() {
    registerFallbackValue(const LocationSettings(accuracy: LocationAccuracy.high));
  });

  void stubEnabledPermission({
    bool enabled = true,
    LocationPermission permission = LocationPermission.whileInUse,
    LocationPermission requestedPermission = LocationPermission.denied,
  }) {
    when(() => mockGeolocator.isLocationServiceEnabled())
        .thenAnswer((_) async => enabled);
    when(() => mockGeolocator.checkPermission())
        .thenAnswer((_) async => permission);
    when(() => mockGeolocator.requestPermission())
        .thenAnswer((_) async => requestedPermission);
  }

  group('checkPermission', () {
    test('returns true when enabled and whileInUse', () async {
      stubEnabledPermission(
        enabled: true,
        permission: LocationPermission.whileInUse,
      );

      expect(await service.checkPermission(), isTrue);
    });

    test('returns true when enabled and always', () async {
      stubEnabledPermission(
        enabled: true,
        permission: LocationPermission.always,
      );

      expect(await service.checkPermission(), isTrue);
    });

    test('returns false when service disabled', () async {
      stubEnabledPermission(enabled: false);

      expect(await service.checkPermission(), isFalse);
    });

    test('returns false when denied and requested also denied', () async {
      stubEnabledPermission(
        enabled: true,
        permission: LocationPermission.denied,
        requestedPermission: LocationPermission.denied,
      );

      expect(await service.checkPermission(), isFalse);
      verify(() => mockGeolocator.requestPermission()).called(1);
    });

    test('requests permission and returns true when user grants whileInUse', () async {
      stubEnabledPermission(
        enabled: true,
        permission: LocationPermission.denied,
        requestedPermission: LocationPermission.whileInUse,
      );

      expect(await service.checkPermission(), isTrue);
      verify(() => mockGeolocator.requestPermission()).called(1);
    });
  });

  group('getLocation', () {
    test('returns PermissionFailure when services disabled', () async {
      when(() => mockGeolocator.isLocationServiceEnabled())
          .thenAnswer((_) async => false);

      final result = await service.getLocation();

      expect(
        result,
        const Left<Failure, Map<String, dynamic>>(
          PermissionFailure('Location services are disabled. Please enable GPS.'),
        ),
      );
    });

    test('requests permission when denied then succeeds', () async {
      when(() => mockGeolocator.isLocationServiceEnabled())
          .thenAnswer((_) async => true);
      when(() => mockGeolocator.checkPermission())
          .thenAnswer((_) async => LocationPermission.denied);
      when(() => mockGeolocator.requestPermission())
          .thenAnswer((_) async => LocationPermission.whileInUse);
      when(
        () => mockGeolocator.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        ),
      ).thenAnswer((_) async => fakePosition());
      when(() => mockGeocoding.placemarkFromCoordinates(any(), any()))
          .thenAnswer((_) async => []);

      final result = await service.getLocation();

      expect(result.isRight(), isTrue);
      verify(() => mockGeolocator.requestPermission()).called(1);
    });

    test('returns PermissionFailure when still denied after request', () async {
      when(() => mockGeolocator.isLocationServiceEnabled())
          .thenAnswer((_) async => true);
      when(() => mockGeolocator.checkPermission())
          .thenAnswer((_) async => LocationPermission.denied);
      when(() => mockGeolocator.requestPermission())
          .thenAnswer((_) async => LocationPermission.denied);

      final result = await service.getLocation();

      expect(
        result,
        const Left<Failure, Map<String, dynamic>>(
          PermissionFailure('Location permission denied'),
        ),
      );
    });

    test('returns PermissionFailure when deniedForever', () async {
      when(() => mockGeolocator.isLocationServiceEnabled())
          .thenAnswer((_) async => true);
      when(() => mockGeolocator.checkPermission())
          .thenAnswer((_) async => LocationPermission.deniedForever);

      final result = await service.getLocation();

      expect(
        result,
        const Left<Failure, Map<String, dynamic>>(
          PermissionFailure('Location permission permanently denied'),
        ),
      );
    });

    test('returns location with formatted address from placemark', () async {
      stubEnabledPermission();
      when(
        () => mockGeolocator.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        ),
      ).thenAnswer((_) async => fakePosition(lat: 10.0, lng: 20.0));
      when(() => mockGeocoding.placemarkFromCoordinates(10.0, 20.0))
          .thenAnswer(
        (_) async => const [
          Placemark(
            street: 'Main St',
            subLocality: 'Sub',
            locality: 'City',
            administrativeArea: 'State',
            postalCode: '12345',
            country: 'Country',
          ),
        ],
      );

      final result = await service.getLocation();

      expect(result.isRight(), isTrue);
      final data = result.getOrElse(() => <String, dynamic>{});
      expect(data['latitude'], 10.0);
      expect(data['longitude'], 20.0);
      expect(data['lat'], 10.0);
      expect(data['lng'], 20.0);
      expect(
        data['address'],
        'Main St, Sub, City, State, 12345, Country',
      );
    });

    test('falls back to lat,lng when placemarks empty', () async {
      stubEnabledPermission();
      when(
        () => mockGeolocator.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        ),
      ).thenAnswer((_) async => fakePosition(lat: 10.0, lng: 20.0));
      when(() => mockGeocoding.placemarkFromCoordinates(any(), any()))
          .thenAnswer((_) async => []);

      final result = await service.getLocation();

      final data = result.getOrElse(() => <String, dynamic>{});
      expect(data['address'], '10.0, 20.0');
    });

    test('falls back to lat,lng when geocoding throws', () async {
      stubEnabledPermission();
      when(
        () => mockGeolocator.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        ),
      ).thenAnswer((_) async => fakePosition(lat: 10.0, lng: 20.0));
      when(() => mockGeocoding.placemarkFromCoordinates(any(), any()))
          .thenThrow(Exception('geo fail'));

      final result = await service.getLocation();

      final data = result.getOrElse(() => <String, dynamic>{});
      expect(data['address'], '10.0, 20.0');
    });

    test('returns ServerFailure when getCurrentPosition throws', () async {
      stubEnabledPermission();
      when(
        () => mockGeolocator.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        ),
      ).thenThrow(Exception('gps fail'));
      when(() => mockGeocoding.placemarkFromCoordinates(any(), any()))
          .thenAnswer((_) async => []);

      final result = await service.getLocation();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) {
          expect(failure, isA<ServerFailure>());
          expect(failure.message, contains('Location error'));
        },
        (_) => fail('expected Left'),
      );
    });
  });

  group('getLocationFormattedJson', () {
    test('returns json string on success', () async {
      stubEnabledPermission();
      when(
        () => mockGeolocator.getCurrentPosition(
          locationSettings: any(named: 'locationSettings'),
        ),
      ).thenAnswer((_) async => fakePosition(lat: 10.0, lng: 20.0));
      when(() => mockGeocoding.placemarkFromCoordinates(any(), any()))
          .thenAnswer((_) async => []);

      final result = await service.getLocationFormattedJson();

      expect(result.isRight(), isTrue);
      final jsonStr = result.getOrElse(() => '');
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['latitude'], 10.0);
      expect(decoded['address'], '10.0, 20.0');
    });

    test('propagates failure', () async {
      when(() => mockGeolocator.isLocationServiceEnabled())
          .thenAnswer((_) async => false);

      final result = await service.getLocationFormattedJson();

      expect(result.isLeft(), isTrue);
      expect(
        result,
        const Left<Failure, String>(
          PermissionFailure('Location services are disabled. Please enable GPS.'),
        ),
      );
    });
  });

  group('declared window constants', () {
    test('fix window is 8s, geocode window 7s, tool window 16s', () {
      expect(kLocationFixTimeout, const Duration(seconds: 8));
      expect(kLocationGeocodeTimeout, const Duration(seconds: 7));
      expect(kLocationToolWindow, const Duration(seconds: 16));
    });
  });
}
