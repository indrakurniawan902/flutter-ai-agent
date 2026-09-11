import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/device_context_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockBattery mockBattery;
  late MockDeviceInfoPlugin mockDeviceInfo;
  late MockConnectivity mockConnectivity;
  late DeviceContextService service;

  final testPackageInfo = PackageInfo(
    appName: 'Flutter AI Agent',
    packageName: 'id.indra.flutter_ai_agent',
    version: '1.0.0',
    buildNumber: '1',
  );

  final testScreenSpecs = {
    'width': 1080.0,
    'height': 2400.0,
    'pixel_ratio': 2.625,
  };

  setUp(() {
    mockBattery = MockBattery();
    mockDeviceInfo = MockDeviceInfoPlugin();
    mockConnectivity = MockConnectivity();
    service = DeviceContextService(
      battery: mockBattery,
      deviceInfo: mockDeviceInfo,
      connectivity: mockConnectivity,
      packageInfo: testPackageInfo,
      screenSpecsProvider: () => testScreenSpecs,
    );
  });

  group('device_status', () {
    test('returns battery %, charging state, and WiFi status successfully', () async {
      when(() => mockBattery.batteryLevel).thenAnswer((_) async => 85);
      when(() => mockBattery.batteryState)
          .thenAnswer((_) async => BatteryState.charging);
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);

      final result = await service.deviceStatus();

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should not return failure'),
        (data) {
          expect(data['battery_level'], equals(85));
          expect(data['battery_percentage'], equals(85));
          expect(data['charging_state'], equals('charging'));
          expect(data['is_charging'], isTrue);
          expect(data['wifi_cellular_status'], equals('wifi'));
          expect(data['connectivity'], equals('wifi'));
        },
      );
    });

    test('returns cellular connection status correctly', () async {
      when(() => mockBattery.batteryLevel).thenAnswer((_) async => 42);
      when(() => mockBattery.batteryState)
          .thenAnswer((_) async => BatteryState.discharging);
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.mobile]);

      final result = await service.deviceStatus();

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should not return failure'),
        (data) {
          expect(data['battery_level'], equals(42));
          expect(data['charging_state'], equals('discharging'));
          expect(data['is_charging'], isFalse);
          expect(data['wifi_cellular_status'], equals('cellular'));
        },
      );
    });

    test('returns none when disconnected', () async {
      when(() => mockBattery.batteryLevel).thenAnswer((_) async => 15);
      when(() => mockBattery.batteryState)
          .thenAnswer((_) async => BatteryState.discharging);
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.none]);

      final result = await service.deviceStatus();

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should not return failure'),
        (data) {
          expect(data['wifi_cellular_status'], equals('none'));
          expect(data['connectivity'], equals('none'));
        },
      );
    });

    test('returns ServerFailure when batteryLevel throws', () async {
      when(() => mockBattery.batteryLevel).thenThrow(Exception('Battery error'));
      when(() => mockBattery.batteryState)
          .thenAnswer((_) async => BatteryState.charging);
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);

      final result = await service.deviceStatus();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (data) => fail('Should not return data'),
      );
    });

    test('returns ServerFailure when connectivity throws', () async {
      when(() => mockBattery.batteryLevel).thenAnswer((_) async => 85);
      when(() => mockBattery.batteryState)
          .thenAnswer((_) async => BatteryState.charging);
      when(() => mockConnectivity.checkConnectivity())
          .thenThrow(Exception('Network error'));

      final result = await service.deviceStatus();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (data) => fail('Should not return data'),
      );
    });

    test('deviceStatusFormattedJson returns valid JSON string matching OpenAI tool format', () async {
      when(() => mockBattery.batteryLevel).thenAnswer((_) async => 90);
      when(() => mockBattery.batteryState)
          .thenAnswer((_) async => BatteryState.full);
      when(() => mockConnectivity.checkConnectivity())
          .thenAnswer((_) async => [ConnectivityResult.wifi]);

      final result = await service.deviceStatusFormattedJson();

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should not return failure'),
        (jsonString) {
          final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
          expect(decoded['battery_level'], equals(90));
          expect(decoded['charging_state'], equals('full'));
          expect(decoded['wifi_cellular_status'], equals('wifi'));
        },
      );
    });
  });

  group('system_info', () {
    test('returns Android system info correctly', () async {
      when(() => mockDeviceInfo.deviceInfo).thenAnswer(
        (_) async => BaseDeviceInfo({
          'model': 'Pixel 8',
          'manufacturer': 'Google',
          'version': {'release': '14', 'sdkInt': 34},
        }),
      );

      final result = await service.systemInfo();

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should not return failure'),
        (data) {
          expect(data['device_model'], contains('Pixel 8'));
          expect(data['os_version'], contains('14'));
          expect(data['app_version'], equals('1.0.0+1'));
          expect(data['screen_specs'], equals(testScreenSpecs));
        },
      );
    });

    test('returns iOS system info correctly', () async {
      when(() => mockDeviceInfo.deviceInfo).thenAnswer(
        (_) async => BaseDeviceInfo({
          'model': 'iPhone',
          'name': "Indra's iPhone",
          'systemName': 'iOS',
          'systemVersion': '17.2',
          'utsname': {'machine': 'iPhone15,2'},
        }),
      );

      final result = await service.systemInfo();

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should not return failure'),
        (data) {
          expect(data['device_model'], isNotEmpty);
          expect(data['os_version'], contains('17.2'));
          expect(data['app_version'], equals('1.0.0+1'));
          expect(data['screen_specs'], equals(testScreenSpecs));
        },
      );
    });

    test('returns ServerFailure when deviceInfo throws', () async {
      when(() => mockDeviceInfo.deviceInfo).thenThrow(Exception('Device info error'));

      final result = await service.systemInfo();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (data) => fail('Should not return data'),
      );
    });

    test('systemInfoFormattedJson returns valid JSON string matching OpenAI tool format', () async {
      when(() => mockDeviceInfo.deviceInfo).thenAnswer(
        (_) async => BaseDeviceInfo({
          'model': 'Linux Desktop',
          'name': 'Ubuntu',
          'version': '24.04',
        }),
      );

      final result = await service.systemInfoFormattedJson();

      expect(result.isRight(), isTrue);
      result.fold(
        (failure) => fail('Should not return failure'),
        (jsonString) {
          final decoded = jsonDecode(jsonString) as Map<String, dynamic>;
          expect(decoded['device_model'], isNotEmpty);
          expect(decoded['app_version'], equals('1.0.0+1'));
          expect(decoded['screen_specs'], equals(testScreenSpecs));
        },
      );
    });
  });
}
