import 'dart:convert';
import 'dart:ui';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dartz/dartz.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:injectable/injectable.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/domain/tools/chat/device_context_service.dart';

@LazySingleton(as: DeviceContextServiceBase)
class DeviceContextService implements DeviceContextServiceBase {
  DeviceContextService({
    Battery? battery,
    DeviceInfoPlugin? deviceInfo,
    Connectivity? connectivity,
    this.packageInfo,
    this.screenSpecsProvider,
  })  : _battery = battery ?? Battery(),
        _deviceInfo = deviceInfo ?? DeviceInfoPlugin(),
        _connectivity = connectivity ?? Connectivity();

  @factoryMethod
  factory DeviceContextService.create() => DeviceContextService();

  final Battery _battery;
  final DeviceInfoPlugin _deviceInfo;
  final Connectivity _connectivity;
  final PackageInfo? packageInfo;
  final Map<String, dynamic> Function()? screenSpecsProvider;

  @override
  Future<Either<Failure, Map<String, dynamic>>> deviceStatus() async {
    try {
      final batteryLevel = await _battery.batteryLevel;
      final batteryState = await _battery.batteryState;
      final connectivityResults = await _connectivity.checkConnectivity();

      final chargingState = switch (batteryState) {
        BatteryState.charging => 'charging',
        BatteryState.discharging => 'discharging',
        BatteryState.full => 'full',
        BatteryState.connectedNotCharging => 'connectedNotCharging',
        BatteryState.unknown => 'unknown',
      };

      final isCharging = batteryState == BatteryState.charging;
      final networkStatus = _resolveNetworkStatus(connectivityResults);

      final data = <String, dynamic>{
        'battery_level': batteryLevel,
        'battery_percentage': batteryLevel,
        'charging_state': chargingState,
        'is_charging': isCharging,
        'wifi_cellular_status': networkStatus,
        'connectivity': networkStatus,
      };

      return Right(data);
    } catch (e) {
      return Left(ServerFailure('Device status error: $e'));
    }
  }

  @override
  Future<Either<Failure, Map<String, dynamic>>> systemInfo() async {
    try {
      final baseInfo = await _deviceInfo.deviceInfo;
      final dataMap = baseInfo.data;

      final model = _resolveModel(dataMap);
      final osVersion = _resolveOsVersion(dataMap);
      final appVersion = await _resolveAppVersion();
      final screenSpecs = screenSpecsProvider != null
          ? screenSpecsProvider!()
          : _resolveScreenSpecs();

      final info = <String, dynamic>{
        'device_model': model,
        'model': model,
        'os_version': osVersion,
        'app_version': appVersion,
        'screen_specs': screenSpecs,
      };

      return Right(info);
    } catch (e) {
      return Left(ServerFailure('System info error: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> deviceStatusFormattedJson() async {
    final statusResult = await deviceStatus();
    return statusResult.map((data) => jsonEncode(data));
  }

  @override
  Future<Either<Failure, String>> systemInfoFormattedJson() async {
    final infoResult = await systemInfo();
    return infoResult.map((data) => jsonEncode(data));
  }

  String _resolveNetworkStatus(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      return 'wifi';
    } else if (results.contains(ConnectivityResult.mobile)) {
      return 'cellular';
    } else if (results.contains(ConnectivityResult.ethernet)) {
      return 'ethernet';
    } else if (results.contains(ConnectivityResult.vpn)) {
      return 'vpn';
    } else if (results.contains(ConnectivityResult.none) || results.isEmpty) {
      return 'none';
    }
    return 'unknown';
  }

  String _resolveModel(Map<String, dynamic> data) {
    if (data.containsKey('model') && data['model'] != null) {
      final model = data['model'].toString();
      final manufacturer = data['manufacturer']?.toString();
      if (manufacturer != null && !model.toLowerCase().contains(manufacturer.toLowerCase())) {
        return '$manufacturer $model';
      }
      return model;
    }
    if (data.containsKey('name') && data['name'] != null) {
      return data['name'].toString();
    }
    if (data.containsKey('computerName') && data['computerName'] != null) {
      return data['computerName'].toString();
    }
    return 'Unknown Device';
  }

  String _resolveOsVersion(Map<String, dynamic> data) {
    if (data.containsKey('version')) {
      final v = data['version'];
      if (v is Map) {
        final release = v['release'] ?? '';
        final sdk = v['sdkInt'] != null ? ' (SDK ${v['sdkInt']})' : '';
        return 'Android $release$sdk'.trim();
      }
      return v.toString();
    }
    if (data.containsKey('systemVersion')) {
      final sysName = data['systemName'] ?? 'iOS';
      return '$sysName ${data['systemVersion']}';
    }
    if (data.containsKey('osRelease')) {
      return 'macOS ${data['osRelease']}';
    }
    if (data.containsKey('productName')) {
      return 'Windows ${data['productName']}';
    }
    return 'Unknown OS';
  }

  Future<String> _resolveAppVersion() async {
    if (packageInfo != null) {
      return '${packageInfo!.version}+${packageInfo!.buildNumber}';
    }
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '1.0.0+1';
    }
  }

  Map<String, dynamic> _resolveScreenSpecs() {
    try {
      final views = PlatformDispatcher.instance.views;
      if (views.isNotEmpty) {
        final view = views.first;
        final pixelRatio = view.devicePixelRatio > 0 ? view.devicePixelRatio : 1.0;
        return {
          'width': view.physicalSize.width / pixelRatio,
          'height': view.physicalSize.height / pixelRatio,
          'pixel_ratio': pixelRatio,
        };
      }
    } catch (_) {}
    return {
      'width': 0.0,
      'height': 0.0,
      'pixel_ratio': 1.0,
    };
  }
}
