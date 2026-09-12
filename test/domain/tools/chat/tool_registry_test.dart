import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockClipboardService extends Mock implements ClipboardServiceBase {}

class MockLocationService extends Mock implements LocationServiceBase {}

class MockFileWorkspaceService extends Mock implements FileWorkspaceServiceBase {}

class MockNotificationTriageService extends Mock
    implements NotificationTriageServiceBase {}

class MockLocalMemoryService extends Mock implements LocalMemoryServiceBase {}

class MockAmbientTriggerService extends Mock
    implements AmbientTriggerServiceBase {}

void main() {
  late ToolRegistry registry;
  late MockClipboardService mockClipboard;
  late MockLocationService mockLocation;

  setUp(() {
    registry = ToolRegistry();
    mockClipboard = MockClipboardService();
    mockLocation = MockLocationService();
  });

  RegisteredTool sampleTool({SecurityTier tier = SecurityTier.tier1Auto}) {
    return RegisteredTool(
      name: 'sample',
      description: 'sample tool',
      parameters: const {
        'type': 'object',
        'properties': {},
      },
      securityTier: tier,
      execute: (_) async => const Right('ok'),
    );
  }

  group('register / lookup', () {
    test('register, hasTool, getTool, tools', () {
      expect(registry.hasTool('sample'), isFalse);

      registry.register(sampleTool());

      expect(registry.hasTool('sample'), isTrue);
      expect(registry.getTool('sample')?.name, 'sample');
      expect(registry.tools.map((t) => t.name), contains('sample'));
    });

    test('getOpenAiToolDefinitions returns OpenAI shape', () {
      registry.register(sampleTool());

      final defs = registry.getOpenAiToolDefinitions();

      expect(defs, hasLength(1));
      expect(defs.first['type'], 'function');
      expect(defs.first['function']['name'], 'sample');
    });

    test('toOpenAiTool shape', () {
      final tool = sampleTool();

      final map = tool.toOpenAiTool();

      expect(map['type'], 'function');
      expect(map['function']['name'], 'sample');
      expect(map['function']['description'], 'sample tool');
      expect(map['function']['parameters'], isA<Map>());
    });
  });

  group('executeTool', () {
    test('returns ServerFailure when tool not found', () async {
      final result = await registry.executeTool('missing');

      expect(
        result,
        const Left<Failure, String>(ServerFailure('Tool not found: missing')),
      );
    });

    test('executes tool and returns result', () async {
      registry.register(sampleTool());

      final result = await registry.executeTool('sample');

      expect(result, const Right<Failure, String>('ok'));
    });

    test('tier2 permission denied returns PermissionFailure', () async {
      registry.register(
        RegisteredTool(
          name: 'gated',
          description: 'gated',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier2Permission,
          execute: (_) async => const Right('should not run'),
          checkPermission: () async => false,
        ),
      );

      final result = await registry.executeTool('gated');

      expect(
        result,
        const Left<Failure, String>(
          PermissionFailure('Permission denied for tool: gated'),
        ),
      );
    });

    test('tier2 permission granted executes', () async {
      registry.register(
        RegisteredTool(
          name: 'gated',
          description: 'gated',
          parameters: const {'type': 'object'},
          securityTier: SecurityTier.tier2Permission,
          execute: (_) async => const Right('ran'),
          checkPermission: () async => true,
        ),
      );

      final result = await registry.executeTool('gated');

      expect(result, const Right<Failure, String>('ran'));
    });
  });

  group('registerClipboardTools', () {
    test('registers clipboard_read and clipboard_write as tier1', () async {
      when(() => mockClipboard.clipboardRead())
          .thenAnswer((_) async => const Right('clip'));
      when(() => mockClipboard.clipboardWrite(any()))
          .thenAnswer((_) async => const Right('Text copied to clipboard'));

      registry.registerClipboardTools(mockClipboard);

      expect(registry.hasTool('clipboard_read'), isTrue);
      expect(registry.hasTool('clipboard_write'), isTrue);
      expect(
        registry.getTool('clipboard_read')?.securityTier,
        SecurityTier.tier1Auto,
      );
      expect(
        registry.getTool('clipboard_write')?.securityTier,
        SecurityTier.tier1Auto,
      );

      final readResult = await registry.executeTool('clipboard_read');
      expect(readResult, const Right<Failure, String>('clip'));

      final writeResult =
          await registry.executeTool('clipboard_write', {'text': 'hi'});
      expect(writeResult, const Right<Failure, String>('Text copied to clipboard'));
      verify(() => mockClipboard.clipboardWrite('hi')).called(1);
    });
  });

  group('registerLocationTools', () {
    test('registers get_location as tier2 with permission check', () async {
      when(() => mockLocation.checkPermission())
          .thenAnswer((_) async => true);
      when(
        () => mockLocation.getLocationFormattedJson(
          accuracy: any(named: 'accuracy'),
        ),
      ).thenAnswer((_) async => const Right('{"lat":1}'));

      registry.registerLocationTools(mockLocation);

      expect(registry.hasTool('get_location'), isTrue);
      expect(
        registry.getTool('get_location')?.securityTier,
        SecurityTier.tier2Permission,
      );

      final result =
          await registry.executeTool('get_location', {'accuracy': 'high'});
      expect(result, const Right<Failure, String>('{"lat":1}'));
      verify(() => mockLocation.checkPermission()).called(1);
    });

    test('denies execution when permission check fails', () async {
      when(() => mockLocation.checkPermission())
          .thenAnswer((_) async => false);

      registry.registerLocationTools(mockLocation);

      final result = await registry.executeTool('get_location');

      expect(
        result,
        const Left<Failure, String>(
          PermissionFailure('Permission denied for tool: get_location'),
        ),
      );
    });
  });

  group('registerFileWorkspaceTools', () {
    late MockFileWorkspaceService mockFiles;

    setUp(() {
      mockFiles = MockFileWorkspaceService();
    });

    test('registers tools with proper tiers and executes', () async {
      when(() => mockFiles.checkPermission()).thenAnswer((_) async => true);
      when(
        () => mockFiles.readFile(
          any(),
          maxLines: any(named: 'maxLines'),
          offset: any(named: 'offset'),
        ),
      ).thenAnswer((_) async => const Right('file-content'));
      when(
        () => mockFiles.listFilesFormattedJson(
          any(),
          recursive: any(named: 'recursive'),
        ),
      ).thenAnswer((_) async => const Right('[]'));

      registry.registerFileWorkspaceTools(mockFiles);

      expect(registry.hasTool('read_device_file'), isTrue);
      expect(registry.hasTool('list_device_files'), isTrue);
      expect(
        registry.getTool('read_device_file')?.securityTier,
        SecurityTier.tier2Permission,
      );
      expect(
        registry.getTool('list_device_files')?.securityTier,
        SecurityTier.tier1Auto,
      );

      final readResult = await registry.executeTool(
        'read_device_file',
        {'path': '/tmp/a.txt', 'maxLines': 10, 'offset': 2},
      );
      expect(readResult, const Right<Failure, String>('file-content'));
      verify(
        () => mockFiles.readFile('/tmp/a.txt', maxLines: 10, offset: 2),
      ).called(1);

      final listResult = await registry.executeTool(
        'list_device_files',
        {'directoryPath': '/tmp', 'recursive': true},
      );
      expect(listResult, const Right<Failure, String>('[]'));
      verify(
        () => mockFiles.listFilesFormattedJson('/tmp', recursive: true),
      ).called(1);
    });

    test('denies read_device_file when permission fails', () async {
      when(() => mockFiles.checkPermission()).thenAnswer((_) async => false);

      registry.registerFileWorkspaceTools(mockFiles);

      final result = await registry.executeTool(
        'read_device_file',
        {'path': '/tmp/a.txt'},
      );
      expect(
        result,
        const Left<Failure, String>(
          PermissionFailure('Permission denied for tool: read_device_file'),
        ),
      );
    });
  });

  group('registerNotificationTriageTools', () {
    late MockNotificationTriageService mockTriage;

    setUp(() {
      mockTriage = MockNotificationTriageService();
    });

    test('registers tools with proper tiers and executes', () async {
      when(() => mockTriage.checkPermission()).thenAnswer((_) async => true);
      when(
        () => mockTriage.readRecentNotificationsFormattedJson(
          limit: any(named: 'limit'),
          appFilter: any(named: 'appFilter'),
        ),
      ).thenAnswer((_) async => const Right('[]'));
      when(
        () => mockTriage.extractLatestOtpFormattedJson(
          appFilter: any(named: 'appFilter'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => const Right('{"found":false}'));

      registry.registerNotificationTriageTools(mockTriage);

      expect(registry.hasTool('read_recent_notifications'), isTrue);
      expect(registry.hasTool('extract_latest_otp'), isTrue);
      expect(
        registry.getTool('read_recent_notifications')?.securityTier,
        SecurityTier.tier2Permission,
      );
      expect(
        registry.getTool('extract_latest_otp')?.securityTier,
        SecurityTier.tier2Permission,
      );

      final readResult = await registry.executeTool(
        'read_recent_notifications',
        {'limit': 5, 'appFilter': 'sms'},
      );
      expect(readResult, const Right<Failure, String>('[]'));

      final otpResult = await registry.executeTool(
        'extract_latest_otp',
        {'appFilter': 'sms', 'limit': 5},
      );
      expect(otpResult, const Right<Failure, String>('{"found":false}'));
      verify(() => mockTriage.checkPermission()).called(2);
    });

    test('denies when permission fails', () async {
      when(() => mockTriage.checkPermission()).thenAnswer((_) async => false);

      registry.registerNotificationTriageTools(mockTriage);

      final result = await registry.executeTool('read_recent_notifications');
      expect(
        result,
        const Left<Failure, String>(
          PermissionFailure(
            'Permission denied for tool: read_recent_notifications',
          ),
        ),
      );
    });
  });

  group('registerMemoryTools', () {
    late MockLocalMemoryService mockMemory;

    setUp(() {
      mockMemory = MockLocalMemoryService();
    });

    test('registers tools with proper tiers and executes', () async {
      when(() => mockMemory.saveMemoryFormattedJson(any()))
          .thenAnswer((_) async => const Right('{"status":"saved"}'));
      when(() => mockMemory.searchMemoriesFormattedJson(any()))
          .thenAnswer((_) async => const Right('{"count":1}'));
      when(() => mockMemory.deleteMemoryFormattedJson(any()))
          .thenAnswer((_) async => const Right('{"status":"deleted"}'));
      when(() => mockMemory.listMemoriesFormattedJson(any()))
          .thenAnswer((_) async => const Right('{"count":0}'));

      registry.registerMemoryTools(mockMemory);

      for (final name in [
        'save_memory',
        'search_memories',
        'delete_memory',
        'list_memories',
      ]) {
        expect(registry.hasTool(name), isTrue);
        expect(
          registry.getTool(name)?.securityTier,
          SecurityTier.tier1Auto,
        );
      }

      expect(
        await registry.executeTool('save_memory', {'key': 'k'}),
        const Right<Failure, String>('{"status":"saved"}'),
      );
      expect(
        await registry.executeTool('search_memories', {'query': 'q'}),
        const Right<Failure, String>('{"count":1}'),
      );
      expect(
        await registry.executeTool('delete_memory', {'key': 'k'}),
        const Right<Failure, String>('{"status":"deleted"}'),
      );
      expect(
        await registry.executeTool('list_memories', {'limit': 10}),
        const Right<Failure, String>('{"count":0}'),
      );
      verify(() => mockMemory.saveMemoryFormattedJson(any())).called(1);
      verify(() => mockMemory.searchMemoriesFormattedJson(any())).called(1);
      verify(() => mockMemory.deleteMemoryFormattedJson(any())).called(1);
      verify(() => mockMemory.listMemoriesFormattedJson(any())).called(1);
    });
  });

  group('registerAmbientTriggerTools', () {
    late MockAmbientTriggerService mockAmbient;

    setUp(() {
      mockAmbient = MockAmbientTriggerService();
      registerFallbackValue(
        const GeofenceRegion(
          id: 'fallback',
          latitude: 0,
          longitude: 0,
          radiusMeters: 100,
        ),
      );
    });

    test('registers tools with proper tiers and executes', () async {
      when(() => mockAmbient.regions).thenReturn(const [
        GeofenceRegion(
          id: 'home',
          latitude: 1,
          longitude: 2,
          radiusMeters: 100,
        ),
      ]);
      when(() => mockAmbient.lowThreshold).thenReturn(20);
      when(() => mockAmbient.criticalThreshold).thenReturn(10);
      when(() => mockAmbient.cooldown).thenReturn(const Duration(hours: 1));
      when(
        () => mockAmbient.checkAll(
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
          now: any(named: 'now'),
        ),
      ).thenAnswer(
        (_) async => Right(AmbientCheckResult.empty()),
      );

      registry.registerAmbientTriggerTools(mockAmbient);

      for (final name in [
        'register_geofence',
        'list_geofences',
        'remove_geofence',
        'check_ambient_status',
        'trigger_ambient_check',
      ]) {
        expect(registry.hasTool(name), isTrue);
        expect(
          registry.getTool(name)?.securityTier,
          SecurityTier.tier1Auto,
        );
      }

      final registerResult = await registry.executeTool('register_geofence', {
        'id': 'office',
        'latitude': 1.0,
        'longitude': 2.0,
        'radiusMeters': 50.0,
      });
      expect(registerResult.isRight(), isTrue);
      verify(() => mockAmbient.addGeofence(any())).called(1);

      final listResult = await registry.executeTool('list_geofences');
      expect(listResult.isRight(), isTrue);
      expect(listResult.getOrElse(() => ''), contains('home'));

      final removeResult = await registry.executeTool(
        'remove_geofence',
        {'id': 'home'},
      );
      expect(removeResult, const Right<Failure, String>('Geofence removed: home'));
      verify(() => mockAmbient.removeGeofence('home')).called(1);

      final statusResult =
          await registry.executeTool('check_ambient_status');
      expect(statusResult.isRight(), isTrue);
      expect(statusResult.getOrElse(() => ''), contains('geofenceCount'));

      final triggerResult = await registry.executeTool(
        'trigger_ambient_check',
        {'latitude': 1.0, 'longitude': 2.0},
      );
      expect(triggerResult.isRight(), isTrue);
    });
  });
}
