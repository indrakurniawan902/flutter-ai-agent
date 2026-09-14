import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/external_camera_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockExternalCameraService extends Mock
    implements ExternalCameraServiceBase {}

Future<bool> _granted() async => true;

ExternalCameraDevice _device({
  int deviceId = 7,
  String name = 'USB Camera',
  int vendorId = 0x2bc5,
  int productId = 0x0609,
  String manufacturer = 'ACME',
  String serialNumber = 'SN-42',
  bool hasPermission = true,
}) => ExternalCameraDevice(
  deviceId: deviceId,
  name: name,
  vendorId: vendorId,
  productId: productId,
  manufacturer: manufacturer,
  serialNumber: serialNumber,
  hasPermission: hasPermission,
);

void main() {
  late MockExternalCameraService service;
  late ToolRegistry registry;

  const frame = ExternalCameraFrame(
    width: 1280,
    height: 720,
    base64Jpeg: 'ZmFrZS1qcGVnLWJhc2U2NA==',
  );

  setUpAll(() {
    registerFallbackValue(_granted);
  });

  setUp(() {
    service = MockExternalCameraService();
    registry = ToolRegistry(externalCameraService: service);
  });

  group('registration', () {
    test('registers exactly the 3 external camera tools with unique names',
        () {
      expect(registry.hasTool('external_camera_list'), isTrue);
      expect(registry.hasTool('external_camera_capture'), isTrue);
      expect(registry.hasTool('external_camera_status'), isTrue);

      final names = registry.tools.map((t) => t.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('all 3 tool definitions are schema-valid', () {
      for (final name in const [
        'external_camera_list',
        'external_camera_capture',
        'external_camera_status',
      ]) {
        final tool = registry.getTool(name)!;
        final def = tool.toOpenAiTool();
        expect(def['type'], 'function');
        final function = def['function'] as Map<String, dynamic>;
        expect(function['name'], name);
        expect((function['description'] as String).isNotEmpty, isTrue);
        final parameters = Map<String, dynamic>.from(
          function['parameters'] as Map,
        );
        expect(parameters['type'], 'object');
        final properties = Map<String, dynamic>.from(
          parameters['properties'] as Map,
        ).keys.toSet();
        for (final required in parameters['required'] as List) {
          expect(properties.contains(required), isTrue,
              reason: '$name requires unknown property $required');
        }
      }
    });

    test('descriptions flag USB and point at camera_take_photo for built-in',
        () {
      for (final name in const [
        'external_camera_list',
        'external_camera_capture',
        'external_camera_status',
      ]) {
        final description = registry.getTool(name)!.description.toLowerCase();
        expect(description.contains('usb'), isTrue, reason: name);
        expect(description.contains('camera_take_photo'), isTrue, reason: name);
      }
    });

    test('security tiers: list/status tier1Auto, capture tier2Permission', () {
      final list = registry.getTool('external_camera_list')!;
      final status = registry.getTool('external_camera_status')!;
      final capture = registry.getTool('external_camera_capture')!;

      expect(list.securityTier, SecurityTier.tier1Auto);
      expect(status.securityTier, SecurityTier.tier1Auto);
      expect(capture.securityTier, SecurityTier.tier2Permission);

      expect(list.checkPermission, isNull);
      expect(status.checkPermission, isNull);
      expect(capture.checkPermission, isNotNull);
    });
  });

  group('external_camera_capture', () {
    test('denied camera permission returns PermissionFailure and never opens',
        () async {
      when(() => service.isCameraPermissionGranted())
          .thenAnswer((_) async => false);

      final res = await registry.executeTool('external_camera_capture');

      expect(res.isLeft(), isTrue);
      expect((res as Left).value, isA<PermissionFailure>());
      verifyNever(() => service.openDevice(
            any(),
            ensureCameraPermission: any(named: 'ensureCameraPermission'),
          ));
      verifyNever(() => service.capture(quality: any(named: 'quality')));
    });

    test('already-open device captures without reopening', () async {
      when(() => service.isCameraPermissionGranted())
          .thenAnswer((_) async => true);
      when(() => service.status).thenReturn(
        const ExternalCameraStatus(
          isDeviceOpen: true,
          isPreviewing: true,
          mode: ExternalCameraPreviewMode(
            width: 1280,
            height: 720,
            fps: 30,
            formatName: 'MJPEG',
          ),
          openedDeviceId: 7,
          deviceName: 'USB Camera',
        ),
      );
      when(() => service.capture(quality: any(named: 'quality')))
          .thenAnswer((_) async => const Right(frame));

      final res = await registry.executeTool('external_camera_capture');

      expect(res.isRight(), isTrue);
      expect((res as Right).value, frame.base64Jpeg);
      verifyNever(() => service.openDevice(
            any(),
            ensureCameraPermission: any(named: 'ensureCameraPermission'),
          ));
    });

    test('listed device without USB permission returns PermissionFailure',
        () async {
      when(() => service.isCameraPermissionGranted())
          .thenAnswer((_) async => true);
      when(() => service.status)
          .thenReturn(const ExternalCameraStatus.closed());
      when(() => service.listDevices()).thenAnswer(
        (_) async => Right([_device(hasPermission: false)]),
      );

      final res =
          await registry.executeTool('external_camera_capture', {'deviceId': 7});

      expect(res.isLeft(), isTrue);
      expect((res as Left).value, isA<PermissionFailure>());
      verifyNever(() => service.openDevice(
            any(),
            ensureCameraPermission: any(named: 'ensureCameraPermission'),
          ));
      verifyNever(() => service.capture(quality: any(named: 'quality')));
    });

    test('granted + permitted device opens it and returns the frame',
        () async {
      when(() => service.isCameraPermissionGranted())
          .thenAnswer((_) async => true);
      when(() => service.status)
          .thenReturn(const ExternalCameraStatus.closed());
      when(() => service.listDevices())
          .thenAnswer((_) async => Right([_device(deviceId: 7)]));
      when(() => service.openDevice(
            7,
            ensureCameraPermission: any(named: 'ensureCameraPermission'),
          )).thenAnswer(
        (_) async => const Right(
          ExternalCameraPreviewMode(
            width: 1280,
            height: 720,
            fps: 30,
            formatName: 'MJPEG',
          ),
        ),
      );
      when(() => service.capture(quality: any(named: 'quality')))
          .thenAnswer((_) async => const Right(frame));

      final res =
          await registry.executeTool('external_camera_capture', {'deviceId': 7});

      expect(res.isRight(), isTrue);
      expect((res as Right).value, frame.base64Jpeg);
      verify(() => service.openDevice(
            7,
            ensureCameraPermission: any(named: 'ensureCameraPermission'),
          )).called(1);
    });

    test('empty device list returns ServerFailure', () async {
      when(() => service.isCameraPermissionGranted())
          .thenAnswer((_) async => true);
      when(() => service.status)
          .thenReturn(const ExternalCameraStatus.closed());
      when(() => service.listDevices())
          .thenAnswer((_) async => const Right(<ExternalCameraDevice>[]));

      final res = await registry.executeTool('external_camera_capture');

      expect(res.isLeft(), isTrue);
      expect((res as Left).value, isA<ServerFailure>());
      verifyNever(() => service.openDevice(
            any(),
            ensureCameraPermission: any(named: 'ensureCameraPermission'),
          ));
    });
  });

  group('external_camera_status', () {
    test('returns the open preview state as JSON', () async {
      when(() => service.status).thenReturn(
        const ExternalCameraStatus(
          isDeviceOpen: true,
          isPreviewing: true,
          mode: ExternalCameraPreviewMode(
            width: 1920,
            height: 1080,
            fps: 25,
            formatName: 'YUY2',
          ),
          openedDeviceId: 7,
          deviceName: 'USB Camera',
        ),
      );

      final res = await registry.executeTool('external_camera_status');

      expect(res.isRight(), isTrue);
      final decoded =
          jsonDecode((res as Right).value as String) as Map<String, dynamic>;
      expect(decoded['isDeviceOpen'], isTrue);
      expect(decoded['isPreviewing'], isTrue);
      expect(decoded['deviceId'], 7);
      expect(decoded['deviceName'], 'USB Camera');
      expect(decoded['width'], 1920);
      expect(decoded['height'], 1080);
      expect(decoded['fps'], 25);
      expect(decoded['format'], 'YUY2');
    });

    test('returns nulls when the device is closed', () async {
      when(() => service.status)
          .thenReturn(const ExternalCameraStatus.closed());

      final res = await registry.executeTool('external_camera_status');

      expect(res.isRight(), isTrue);
      final decoded =
          jsonDecode((res as Right).value as String) as Map<String, dynamic>;
      expect(decoded['isDeviceOpen'], isFalse);
      expect(decoded['isPreviewing'], isFalse);
      expect(decoded['deviceId'], isNull);
      expect(decoded['width'], isNull);
      expect(decoded['height'], isNull);
      expect(decoded['fps'], isNull);
    });
  });

  group('external_camera_list', () {
    test('returns device fields and count', () async {
      when(() => service.listDevices()).thenAnswer(
        (_) async => Right([_device()]),
      );

      final res = await registry.executeTool('external_camera_list');

      expect(res.isRight(), isTrue);
      final decoded =
          jsonDecode((res as Right).value as String) as Map<String, dynamic>;
      expect(decoded['count'], 1);
      final devices = decoded['devices'] as List;
      final first = devices.first as Map<String, dynamic>;
      expect(first['deviceId'], 7);
      expect(first['name'], 'USB Camera');
      expect(first['vendorId'], 0x2bc5);
      expect(first['productId'], 0x0609);
      expect(first['manufacturer'], 'ACME');
      expect(first['serialNumber'], 'SN-42');
      expect(first['hasPermission'], isTrue);
      expect(first['displayName'], 'USB Camera (2bc5:609)');
    });

    test('propagates a Left failure from listDevices', () async {
      when(() => service.listDevices())
          .thenAnswer((_) async => const Left(ServerFailure('usb exploded')));

      final res = await registry.executeTool('external_camera_list');

      expect(res.isLeft(), isTrue);
      final failure = (res as Left).value;
      expect(failure, isA<ServerFailure>());
      expect(failure.message, 'usb exploded');
    });
  });
}
