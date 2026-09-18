import 'package:dartz/dartz.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import 'package:flutter_ai_agent/common/failure.dart';

/// Window for a single geolocator fix. Passed as `LocationSettings.timeLimit`, so a
/// device that never returns a fix settles as a failure instead of hanging forever.
const Duration kLocationFixTimeout = Duration(seconds: 8);

/// Inner window for [LocationServiceBase.getLocation]: one fix
/// ([kLocationFixTimeout], 8s) plus reverse geocoding ([kLocationGeocodeTimeout],
/// 7s), plus 1s of headroom so the outer guard cannot race the innermost guards
/// on the same deadline. The registry's outer bound
/// ([ToolRegistry.longWindowToolTimeout], 25s) must stay strictly greater, and
/// the permission pre-check plus this window must stay under the device bridge's
/// 30s budget (see [RegisteredTool.effectivePermissionTimeout]).
const Duration kLocationToolWindow = Duration(seconds: 16);

/// Window for the reverse-geocoding step.
const Duration kLocationGeocodeTimeout = Duration(seconds: 7);

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
