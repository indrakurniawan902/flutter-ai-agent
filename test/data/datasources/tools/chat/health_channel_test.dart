import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/health_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ai.hermes.flames/health');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late DefaultHealthPlatformWrapper wrapper;
  late List<MethodCall> captured;

  setUp(() {
    wrapper = DefaultHealthPlatformWrapper();
    captured = <MethodCall>[];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  group('DefaultHealthPlatformWrapper wire format', () {
    test(
      'availability calls method availability with null arguments',
      () async {
        messenger.setMockMethodCallHandler(channel, (call) async {
          captured.add(call);
          return <String, dynamic>{
            'status': 'available',
            'sdk_int': 34,
            'provider_installed': true,
          };
        });

        final result = await wrapper.availability();

        expect(result, isNotNull);
        expect(result!['status'], 'available');
        expect(captured.single.method, 'availability');
        expect(captured.single.arguments, isNull);
      },
    );

    test('grantedPermissions calls method grantedPermissions', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured.add(call);
        return <String>['android.permission.health.READ_STEPS'];
      });

      final result = await wrapper.grantedPermissions();

      expect(result, <String>['android.permission.health.READ_STEPS']);
      expect(captured.single.method, 'grantedPermissions');
    });

    test('requestPermission calls method requestPermission', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured.add(call);
        return true;
      });

      final result = await wrapper.requestPermission();

      expect(result, isTrue);
      expect(captured.single.method, 'requestPermission');
    });

    test('readMetric sends a Map with metric and int time bounds', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured.add(call);
        return <String, dynamic>{
          'metric': 'steps',
          'start': '2026-09-12T00:00:00.000Z',
          'end': '2026-09-13T00:00:00.000Z',
          'records': <dynamic>[],
          'summary': <String, dynamic>{'total': 0},
        };
      });

      final result = await wrapper.readMetric(
        metric: 'steps',
        startTimeMs: 1000,
        endTimeMs: 2000,
      );

      expect(result, isNotNull);
      final call = captured.single;
      expect(call.method, 'readMetric');
      expect(call.arguments, isA<Map>());
      final args = call.arguments as Map;
      expect(args['metric'], 'steps');
      expect(args['startTimeMs'], 1000);
      expect(args['endTimeMs'], 2000);
    });

    test('swallows PlatformException for every method', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured.add(call);
        throw PlatformException(code: 'boom', message: 'kaboom');
      });

      expect(await wrapper.availability(), isNull);
      expect(await wrapper.grantedPermissions(), isEmpty);
      expect(await wrapper.requestPermission(), isFalse);
      expect(
        await wrapper.readMetric(metric: 'steps', startTimeMs: 0, endTimeMs: 1),
        isNull,
      );
      expect(captured, hasLength(4));
    });
  });
}
