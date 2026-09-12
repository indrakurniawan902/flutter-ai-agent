import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:geolocator/geolocator.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';

@LazySingleton(as: LocationServiceBase)
class LocationService implements LocationServiceBase {
  final GeolocatorPlatformWrapper _geolocator;
  final GeocodingPlatformWrapper _geocoding;

  LocationService({
    GeolocatorPlatformWrapper? geolocator,
    GeocodingPlatformWrapper? geocoding,
  })  : _geolocator = geolocator ?? DefaultGeolocatorPlatformWrapper(),
        _geocoding = geocoding ?? DefaultGeocodingPlatformWrapper();

  @factoryMethod
  factory LocationService.create() => LocationService();

  @override
  Future<bool> checkPermission() async {
    final serviceEnabled = await _geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;
    final permission = await _geolocator.checkPermission();
    return permission == LocationPermission.whileInUse ||
        permission == LocationPermission.always;
  }

  LocationAccuracy _mapAccuracy(String? accuracy) {
    switch (accuracy) {
      case 'low':
        return LocationAccuracy.low;
      case 'medium':
        return LocationAccuracy.medium;
      case 'high':
        return LocationAccuracy.high;
      case 'best':
        return LocationAccuracy.best;
      default:
        return LocationAccuracy.high;
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> getLocation({
    String? accuracy,
  }) async {
    try {
      final serviceEnabled = await _geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const Left(
          PermissionFailure('Location services are disabled. Please enable GPS.'),
        );
      }

      var permission = await _geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await _geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return const Left(
            PermissionFailure('Location permission denied'),
          );
        }
      }
      if (permission == LocationPermission.deniedForever) {
        return const Left(
          PermissionFailure('Location permission permanently denied'),
        );
      }

      final accuracySetting = _mapAccuracy(accuracy);
      final pos = await _geolocator.getCurrentPosition(
        locationSettings: LocationSettings(accuracy: accuracySetting),
      );

      String addressString;
      try {
        final placemarks = await _geocoding.placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final parts = <String>[
            p.street ?? '',
            p.subLocality ?? '',
            p.locality ?? '',
            p.administrativeArea ?? '',
            p.postalCode ?? '',
            p.country ?? '',
          ].where((e) => e.isNotEmpty).toList();
          addressString = parts.isNotEmpty
              ? parts.join(', ')
              : '${pos.latitude}, ${pos.longitude}';
        } else {
          addressString = '${pos.latitude}, ${pos.longitude}';
        }
      } catch (_) {
        addressString = '${pos.latitude}, ${pos.longitude}';
      }

      return Right({
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'lat': pos.latitude,
        'lng': pos.longitude,
        'address': addressString,
      });
    } catch (e) {
      return Left(ServerFailure('Location error: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> getLocationFormattedJson({
    String? accuracy,
  }) async {
    final result = await getLocation(accuracy: accuracy);
    return result.fold(
      (failure) => Left(failure),
      (data) => Right(jsonEncode(data)),
    );
  }
}
