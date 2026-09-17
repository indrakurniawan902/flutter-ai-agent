import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/intent_launcher_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('ai.hermes.flames/intent_settings');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late DefaultSystemSettingsPlatformWrapper wrapper;
  late List<MethodCall> captured;

  setUp(() {
    wrapper = DefaultSystemSettingsPlatformWrapper();
    captured = <MethodCall>[];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  // Regression guard: existing tests inject a mock `SystemSettingsPlatformWrapper`,
  // so a positional-vs-map argument drift on the real MethodChannel wire format
  // would pass CI while `launch_system_setting` silently returns false on device.
  group('DefaultSystemSettingsPlatformWrapper wire format', () {
    test('sends openSystemSettings with a Map {type: settingType} payload',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured.add(call);
        return true;
      });

      final result = await wrapper.openSystemSettings('bluetooth');

      expect(result, isTrue);
      expect(captured, hasLength(1));

      final call = captured.single;
      expect(call.method, 'openSystemSettings');
      expect(call.arguments, isA<Map>());
      expect((call.arguments as Map)['type'], 'bluetooth');
    });

    test('sends the accessibility page as a {type: accessibility} payload',
        () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured.add(call);
        return true;
      });

      final result = await wrapper.openSystemSettings('accessibility');

      expect(result, isTrue);
      expect(captured, hasLength(1));

      final call = captured.single;
      expect(call.method, 'openSystemSettings');
      expect(call.arguments, isA<Map>());
      expect((call.arguments as Map)['type'], 'accessibility');
    });

    test('returns false when native handler replies false', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured.add(call);
        return false;
      });

      final result = await wrapper.openSystemSettings('wifi');

      expect(result, isFalse);
      expect(captured.single.method, 'openSystemSettings');
    });

    test('returns false when native handler replies null', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured.add(call);
        return null;
      });

      final result = await wrapper.openSystemSettings('location');

      expect(result, isFalse);
    });

    test('returns false (swallows) when native handler throws', () async {
      messenger.setMockMethodCallHandler(channel, (call) async {
        captured.add(call);
        throw PlatformException(code: 'boom', message: 'kaboom');
      });

      final result = await wrapper.openSystemSettings('airplane_mode');

      expect(result, isFalse);
      expect(captured.single.method, 'openSystemSettings');
    });
  });
}
