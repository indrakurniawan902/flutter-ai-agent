import 'package:dartz/dartz.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flutter_ai_agent/core/errors/failures.dart';

abstract class LocationServiceBase {
  Future<Either<Failure, Map<String, dynamic>>> getLocation({String? accuracy});
  Future<Either<Failure, String>> getLocationFormattedJson({String? accuracy});
  Future<bool> checkPermission();
}

abstract class GeolocatorPlatformWrapper {
  Future<bool> isLocationServiceEnabled();
  Future<LocationPermission> checkPermission();
  Future<LocationPermission> requestPermission();
  Future<Position> getCurrentPosition({LocationSettings? locationSettings});
}

abstract class GeocodingPlatformWrapper {
  Future<List<Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  );
}

class DefaultGeolocatorPlatformWrapper implements GeolocatorPlatformWrapper {
  @override
  Future<bool> isLocationServiceEnabled() =>
      Geolocator.isLocationServiceEnabled();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationPermission> requestPermission() =>
      Geolocator.requestPermission();

  @override
  Future<Position> getCurrentPosition({LocationSettings? locationSettings}) =>
      Geolocator.getCurrentPosition(locationSettings: locationSettings);
}

class DefaultGeocodingPlatformWrapper implements GeocodingPlatformWrapper {
  @override
  Future<List<Placemark>> placemarkFromCoordinates(
    double latitude,
    double longitude,
  ) =>
      Geocoding().placemarkFromCoordinates(latitude, longitude);
}
