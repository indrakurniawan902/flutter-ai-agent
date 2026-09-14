import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_ai_agent/domain/tools/chat/device_context_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDeviceContextService extends Mock implements DeviceContextServiceBase {}

class MockLocationService extends Mock implements LocationServiceBase {}

class MockNotificationTriageService extends Mock
    implements NotificationTriageServiceBase {}

class MockCameraVisionService extends Mock implements CameraVisionServiceBase {}

class MockContactLauncherTools extends Mock implements ContactLauncherTools {}

class MockLocalMemoryService extends Mock implements LocalMemoryServiceBase {}

void main() {
  late ToolRegistry registry;
  late MockDeviceContextService mockDeviceContext;
  late MockLocationService mockLocation;
  late MockNotificationTriageService mockNotificationTriage;
  late MockCameraVisionService mockCameraVision;
  late MockContactLauncherTools mockContactLauncherTools;
  late MockLocalMemoryService mockLocalMemory;

  setUp(() {
    mockDeviceContext = MockDeviceContextService();
    mockLocation = MockLocationService();
    mockNotificationTriage = MockNotificationTriageService();
    mockCameraVision = MockCameraVisionService();
    mockContactLauncherTools = MockContactLauncherTools();
    mockLocalMemory = MockLocalMemoryService();
    registry = ToolRegistry(
      deviceContextService: mockDeviceContext,
      locationService: mockLocation,
      notificationTriageService: mockNotificationTriage,
      cameraVisionService: mockCameraVision,
      contactLauncherTools: mockContactLauncherTools,
      localMemoryService: mockLocalMemory,
    );
  });

  Future<String> search(String query) async {
    final result = await registry.executeTool('tool_search', {'query': query});
    return result.getOrElse(() => '');
  }

  test('multi-word query finds device_status', () async {
    final result = await search('device status battery');

    expect(result, contains('device_status'));
    expect(result, isNot(contains('No tools matched')));
  });

  test('short query finds device_status', () async {
    final result = await search('battery status');

    expect(result, contains('device_status'));
  });

  test('Indonesian query finds system_info', () async {
    final result = await search('perangkat model informasi');

    expect(result, contains('system_info'));
  });

  test('Indonesian battery query finds device_status', () async {
    final result = await search('cek baterai hp saya');

    expect(result, contains('device_status'));
  });

  test('exact name query lists device_status first', () async {
    final result = await search('device_status');

    expect(result.split('\n').first, equals('device_status'));
  });

  test('all-stopword exact name query self-matches tool_search', () async {
    final result = await search('tool_search');

    expect(result.split('\n'), contains('tool_search'));
    expect(result, isNot(contains('No tools matched')));
  });

  test('unknown query returns actionable sentence', () async {
    final result = await search('zzzqqq nonsense');

    expect(result, isNotEmpty);
    expect(result, contains('No tools matched'));
    expect(result, contains('zzzqqq nonsense'));
    expect(result, contains('Try a single English keyword'));
  });

  test('empty query returns actionable sentence', () async {
    final result = await search('');

    expect(result, isNotEmpty);
    expect(result, contains('No tools matched'));
  });

  test('all-stopword query returns actionable sentence', () async {
    final result = await search('what is my');

    expect(result, isNotEmpty);
    expect(result, contains('No tools matched'));
  });

  test('returned lines are registered names or the actionable sentence',
      () async {
    final names = registry.activeTools.map((t) => t.name).toSet();

    for (final query in <String>['device status battery', 'zzzqqq nonsense']) {
      final result = await search(query);
      for (final line in result.split('\n')) {
        expect(
          names.contains(line) || line.startsWith('No tools matched'),
          isTrue,
        );
      }
    }
  });

  test('disabled tool is excluded from results', () async {
    registry.setToolEnabled('device_status', false);

    final result = await search('device status battery');

    expect(result, isNot(contains('device_status')));
    expect(result, contains('system_info'));
  });
}
