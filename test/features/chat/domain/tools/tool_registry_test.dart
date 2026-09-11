import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/models/ambient_event.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/voice_input_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/background_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/clipboard_service.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/location_service.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/security_policy.dart';
import 'package:flutter_ai_agent/features/chat/domain/tools/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

class MockClipboardService extends Mock implements ClipboardServiceBase {}

class MockLocationService extends Mock implements LocationServiceBase {}

void main() {
  setUpAll(() {
    registerFallbackValue(const GeofenceRegion(
      id: 'fake',
      name: 'fake',
      latitude: 0.0,
      longitude: 0.0,
    ));
  });

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
    late MockFileWorkspaceService mockFileService;

    setUp(() {
      mockFileService = MockFileWorkspaceService();
    });

    test('registers read_device_file and list_device_files with correct safety tiers', () {
      registry.registerFileWorkspaceTools(mockFileService);

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
    });

    test('executes read_device_file when permission is granted', () async {
      when(() => mockFileService.checkPermission())
          .thenAnswer((_) async => true);
      when(() => mockFileService.readFile(any(), maxLines: any(named: 'maxLines'), offset: any(named: 'offset')))
          .thenAnswer((_) async => const Right('file content'));

      registry.registerFileWorkspaceTools(mockFileService);

      final result = await registry.executeTool(
        'read_device_file',
        {'path': '/docs/readme.md', 'maxLines': 10, 'offset': 2},
      );

      expect(result, const Right<Failure, String>('file content'));
      verify(() => mockFileService.checkPermission()).called(1);
      verify(() => mockFileService.readFile('/docs/readme.md', maxLines: 10, offset: 2)).called(1);
    });

    test('denies read_device_file when permission is denied', () async {
      when(() => mockFileService.checkPermission())
          .thenAnswer((_) async => false);

      registry.registerFileWorkspaceTools(mockFileService);

      final result = await registry.executeTool(
        'read_device_file',
        {'path': '/docs/readme.md'},
      );

      expect(
        result,
        const Left<Failure, String>(
          PermissionFailure('Permission denied for tool: read_device_file'),
        ),
      );
      verifyNever(() => mockFileService.readFile(any(), maxLines: any(named: 'maxLines'), offset: any(named: 'offset')));
    });

    test('executes list_device_files with directory path and recursive flag', () async {
      when(() => mockFileService.listFilesFormattedJson(any(), recursive: any(named: 'recursive')))
          .thenAnswer((_) async => const Right('[{"name":"test.txt"}]'));

      registry.registerFileWorkspaceTools(mockFileService);

      final result = await registry.executeTool(
        'list_device_files',
        {'directoryPath': '/workspace', 'recursive': true},
      );

      expect(result, const Right<Failure, String>('[{"name":"test.txt"}]'));
      verify(() => mockFileService.listFilesFormattedJson('/workspace', recursive: true)).called(1);
    });
  });

  group('registerNotificationTriageTools', () {
    late MockNotificationTriageService mockTriageService;

    setUp(() {
      mockTriageService = MockNotificationTriageService();
      registry.registerNotificationTriageTools(mockTriageService);
    });

    test('registers read_recent_notifications and extract_latest_otp as tier2', () {
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
    });

    test('executes read_recent_notifications when permission is granted', () async {
      when(() => mockTriageService.checkPermission()).thenAnswer((_) async => true);
      when(() => mockTriageService.readRecentNotificationsFormattedJson(
            limit: 10,
            appFilter: 'whatsapp',
          )).thenAnswer((_) async => const Right('{"count": 0, "notifications": []}'));

      final result = await registry.executeTool(
        'read_recent_notifications',
        {'limit': 10, 'appFilter': 'whatsapp'},
      );

      expect(result, const Right<Failure, String>('{"count": 0, "notifications": []}'));
      verify(() => mockTriageService.checkPermission()).called(1);
      verify(() => mockTriageService.readRecentNotificationsFormattedJson(
            limit: 10,
            appFilter: 'whatsapp',
          )).called(1);
    });

    test('denies read_recent_notifications when permission is denied', () async {
      when(() => mockTriageService.checkPermission()).thenAnswer((_) async => false);

      final result = await registry.executeTool(
        'read_recent_notifications',
        {},
      );

      expect(
        result,
        const Left<Failure, String>(
          PermissionFailure('Permission denied for tool: read_recent_notifications'),
        ),
      );
      verifyNever(() => mockTriageService.readRecentNotificationsFormattedJson(
            limit: any(named: 'limit'),
            appFilter: any(named: 'appFilter'),
          ));
    });

    test('executes extract_latest_otp when permission is granted', () async {
      when(() => mockTriageService.checkPermission()).thenAnswer((_) async => true);
      when(() => mockTriageService.extractLatestOtpFormattedJson(
            appFilter: 'sms',
          )).thenAnswer((_) async => const Right('{"found": true, "otp": "123456"}'));

      final result = await registry.executeTool(
        'extract_latest_otp',
        {'appFilter': 'sms'},
      );

      expect(result, const Right<Failure, String>('{"found": true, "otp": "123456"}'));
      verify(() => mockTriageService.checkPermission()).called(1);
      verify(() => mockTriageService.extractLatestOtpFormattedJson(appFilter: 'sms')).called(1);
    });

    test('denies extract_latest_otp when permission is denied', () async {
      when(() => mockTriageService.checkPermission()).thenAnswer((_) async => false);

      final result = await registry.executeTool(
        'extract_latest_otp',
        {},
      );

      expect(
        result,
        const Left<Failure, String>(
          PermissionFailure('Permission denied for tool: extract_latest_otp'),
        ),
      );
      verifyNever(() => mockTriageService.extractLatestOtpFormattedJson(
            appFilter: any(named: 'appFilter'),
          ));
    });
  });

  group('registerMemoryTools', () {
    late MockLocalMemoryService mockMemoryService;

    setUp(() {
      mockMemoryService = MockLocalMemoryService();
      registry.registerMemoryTools(mockMemoryService);
    });

    test('registers save_memory, search_memories, delete_memory, and list_memories as tier1Auto', () {
      expect(registry.hasTool('save_memory'), isTrue);
      expect(registry.hasTool('search_memories'), isTrue);
      expect(registry.hasTool('delete_memory'), isTrue);
      expect(registry.hasTool('list_memories'), isTrue);

      expect(registry.getTool('save_memory')?.securityTier, equals(SecurityTier.tier1Auto));
      expect(registry.getTool('search_memories')?.securityTier, equals(SecurityTier.tier1Auto));
      expect(registry.getTool('delete_memory')?.securityTier, equals(SecurityTier.tier1Auto));
      expect(registry.getTool('list_memories')?.securityTier, equals(SecurityTier.tier1Auto));
    });

    test('executes memory tools via ToolRegistry successfully', () async {
      when(() => mockMemoryService.saveMemoryFormattedJson(any()))
          .thenAnswer((_) async => const Right('{"status":"saved"}'));
      when(() => mockMemoryService.searchMemoriesFormattedJson(any()))
          .thenAnswer((_) async => const Right('{"count":1}'));
      when(() => mockMemoryService.deleteMemoryFormattedJson(any()))
          .thenAnswer((_) async => const Right('{"deleted":true}'));
      when(() => mockMemoryService.listMemoriesFormattedJson(any()))
          .thenAnswer((_) async => const Right('{"count":2}'));

      final saveRes = await registry.executeTool('save_memory', {'key': 'k', 'content': 'c'});
      expect(saveRes, equals(const Right('{"status":"saved"}')));

      final searchRes = await registry.executeTool('search_memories', {'query': 'q'});
      expect(searchRes, equals(const Right('{"count":1}')));

      final deleteRes = await registry.executeTool('delete_memory', {'id': 1});
      expect(deleteRes, equals(const Right('{"deleted":true}')));

      final listRes = await registry.executeTool('list_memories', {});
      expect(listRes, equals(const Right('{"count":2}')));
    });
  });

  group('registerAmbientTriggerTools', () {
    late MockAmbientTriggerService mockAmbientService;

    setUp(() {
      mockAmbientService = MockAmbientTriggerService();
      when(() => mockAmbientService.lowBatteryThreshold).thenReturn(15);
      when(() => mockAmbientService.criticalBatteryThreshold).thenReturn(5);
      when(() => mockAmbientService.batteryCooldownDuration)
          .thenReturn(const Duration(minutes: 30));
      when(() => mockAmbientService.geofenceCooldownDuration)
          .thenReturn(const Duration(minutes: 15));
      when(() => mockAmbientService.registeredGeofences).thenReturn([]);
      when(() => mockAmbientService.isUnderCooldown(any())).thenReturn(false);

      registry.registerAmbientTriggerTools(mockAmbientService);
    });

    test('registers 5 ambient tools as tier1Auto', () {
      expect(registry.hasTool('register_geofence'), isTrue);
      expect(registry.hasTool('list_geofences'), isTrue);
      expect(registry.hasTool('remove_geofence'), isTrue);
      expect(registry.hasTool('check_ambient_status'), isTrue);
      expect(registry.hasTool('trigger_ambient_check'), isTrue);

      expect(registry.getTool('register_geofence')?.securityTier,
          equals(SecurityTier.tier1Auto));
      expect(registry.getTool('list_geofences')?.securityTier,
          equals(SecurityTier.tier1Auto));
      expect(registry.getTool('remove_geofence')?.securityTier,
          equals(SecurityTier.tier1Auto));
      expect(registry.getTool('check_ambient_status')?.securityTier,
          equals(SecurityTier.tier1Auto));
      expect(registry.getTool('trigger_ambient_check')?.securityTier,
          equals(SecurityTier.tier1Auto));
    });

    test('executes ambient trigger tools via ToolRegistry successfully', () async {
      when(() => mockAmbientService.registerGeofence(any()))
          .thenAnswer((_) async => const Right(null));
      when(() => mockAmbientService.listGeofences())
          .thenAnswer((_) async => const Right([]));
      when(() => mockAmbientService.removeGeofence(any()))
          .thenAnswer((_) async => const Right(null));
      when(() => mockAmbientService.performPeriodicCheck())
          .thenAnswer((_) async => Right(AmbientCheckResult(
                batteryLevel: 90,
                isCharging: false,
                timestamp: DateTime.utc(2026, 9, 11),
              )));

      final regRes = await registry.executeTool('register_geofence', {
        'id': 'off',
        'name': 'Office',
        'latitude': -6.2,
        'longitude': 106.8,
      });
      expect(regRes.isRight(), isTrue);
      expect(regRes.getOrElse(() => ''), contains('Office'));

      final listRes = await registry.executeTool('list_geofences', {});
      expect(listRes.isRight(), isTrue);

      final remRes = await registry.executeTool('remove_geofence', {'id': 'off'});
      expect(remRes.isRight(), isTrue);

      final statusRes = await registry.executeTool('check_ambient_status', {});
      expect(statusRes.isRight(), isTrue);
      expect(statusRes.getOrElse(() => ''), contains('low_battery_threshold'));

      final checkRes = await registry.executeTool('trigger_ambient_check', {});
      expect(checkRes.isRight(), isTrue);
      expect(checkRes.getOrElse(() => ''), contains('battery_level'));
    });
  });

  group('registerVoiceTools', () {
    late MockVoiceInputService mockVoiceService;

    setUp(() {
      mockVoiceService = MockVoiceInputService();
      registry.registerVoiceTools(mockVoiceService);
    });

    test('registers listen_voice_input as tier2 permission tool', () {
      expect(registry.hasTool('listen_voice_input'), isTrue);
      expect(
        registry.getTool('listen_voice_input')?.securityTier,
        equals(SecurityTier.tier2Permission),
      );
    });

    test('executes listen_voice_input and returns transcribed text on permission grant', () async {
      when(() => mockVoiceService.checkPermission())
          .thenAnswer((_) async => const Right(true));
      when(() => mockVoiceService.statusStream)
          .thenAnswer((_) => Stream.value(VoiceInputStatus.done));
      when(() => mockVoiceService.startListening(
            listenFor: any(named: 'listenFor'),
          )).thenAnswer((_) async => const Right(unit));
      when(() => mockVoiceService.stopListening())
          .thenAnswer((_) async => const Right('Halo Hermit'));

      final result = await registry.executeTool('listen_voice_input', {
        'listenDurationSeconds': 5,
      });

      expect(result, const Right<Failure, String>('Halo Hermit'));
      verify(() => mockVoiceService.startListening(
            listenFor: const Duration(seconds: 5),
          )).called(1);
      verify(() => mockVoiceService.stopListening()).called(1);
    });

    test('denies listen_voice_input when permission is denied', () async {
      when(() => mockVoiceService.checkPermission())
          .thenAnswer((_) async => const Left(PermissionFailure('Mic access denied')));

      final result = await registry.executeTool('listen_voice_input', {});

      expect(
        result,
        const Left<Failure, String>(
          PermissionFailure('Permission denied for tool: listen_voice_input'),
        ),
      );
      verifyNever(() => mockVoiceService.startListening(listenFor: any(named: 'listenFor')));
    });
  });

  group('ToolRegistry - Voice Output Tools', () {
    late ToolRegistry registry;
    late MockVoiceOutputService mockVoiceOutputService;

    setUp(() {
      registry = ToolRegistry();
      mockVoiceOutputService = MockVoiceOutputService();
      registry.registerVoiceOutputTools(mockVoiceOutputService);
    });

    test('registers speak_text as tier1 auto tool', () {
      expect(registry.hasTool('speak_text'), isTrue);
      expect(
        registry.getTool('speak_text')?.securityTier,
        equals(SecurityTier.tier1Auto),
      );
    });

    test('executes speak_text and delegates to voiceOutputService.speakText', () async {
      when(() => mockVoiceOutputService.speakText(
            'Halo dunia',
            voice: any(named: 'voice'),
            model: any(named: 'model'),
            speed: any(named: 'speed'),
          )).thenAnswer((_) async => const Right(unit));

      final result = await registry.executeTool('speak_text', {
        'text': 'Halo dunia',
        'voice': 'alloy',
      });

      expect(result.isRight(), isTrue);
      verify(() => mockVoiceOutputService.speakText(
            'Halo dunia',
            voice: 'alloy',
          )).called(1);
    });

    test('fails validation when text parameter is empty or missing', () async {
      final resultMissing = await registry.executeTool('speak_text', {});
      final resultEmpty = await registry.executeTool('speak_text', {'text': '   '});

      expect(resultMissing.isLeft(), isTrue);
      expect(resultEmpty.isLeft(), isTrue);
      resultMissing.fold(
        (failure) => expect(failure, isA<ValidationFailure>()),
        (_) => fail('Expected Left(ValidationFailure)'),
      );
    });

    test('returns Left(Failure) when voiceOutputService.speakText fails', () async {
      when(() => mockVoiceOutputService.speakText(
            any(),
            voice: any(named: 'voice'),
            model: any(named: 'model'),
            speed: any(named: 'speed'),
          )).thenAnswer((_) async => const Left(ServerFailure('TTS service error')));

      final result = await registry.executeTool('speak_text', {
        'text': 'Error text',
      });

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left(ServerFailure)'),
      );
    });
  });

  group('ToolRegistry - Background Service Tools', () {
    late ToolRegistry registry;
    late MockBackgroundService mockBackgroundService;

    setUp(() {
      registry = ToolRegistry();
      mockBackgroundService = MockBackgroundService();
      registry.registerBackgroundServiceTools(mockBackgroundService);
    });

    test('registers manage_background_service as tier1 auto tool', () {
      expect(registry.hasTool('manage_background_service'), isTrue);
      expect(
        registry.getTool('manage_background_service')?.securityTier,
        equals(SecurityTier.tier1Auto),
      );
    });

    test('executes action "start" and delegates to backgroundService.startService',
        () async {
      when(() => mockBackgroundService.startService(
            title: any(named: 'title'),
            content: any(named: 'content'),
          )).thenAnswer((_) async => const Right(true));

      final result = await registry.executeTool('manage_background_service', {
        'action': 'start',
        'title': 'Agent Active',
        'content': 'Running task in background',
      });

      expect(result.isRight(), isTrue);
      verify(() => mockBackgroundService.startService(
            title: 'Agent Active',
            content: 'Running task in background',
          )).called(1);
    });

    test('executes action "stop" and delegates to backgroundService.stopService',
        () async {
      when(() => mockBackgroundService.stopService())
          .thenAnswer((_) async => const Right(true));

      final result = await registry.executeTool('manage_background_service', {
        'action': 'stop',
      });

      expect(result.isRight(), isTrue);
      verify(() => mockBackgroundService.stopService()).called(1);
    });

    test('executes action "status" and returns service and wakelock state',
        () async {
      when(() => mockBackgroundService.isRunning()).thenAnswer((_) async => true);
      when(() => mockBackgroundService.isWakeLockHeld())
          .thenAnswer((_) async => false);
      when(() => mockBackgroundService.getTileState())
          .thenAnswer((_) async => QuickTileState.active);

      final result = await registry.executeTool('manage_background_service', {
        'action': 'status',
      });

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (text) {
          expect(text, contains('"is_running":true'));
          expect(text, contains('"is_wakelock_held":false'));
          expect(text, contains('"tile_state":"active"'));
        },
      );
    });

    test('executes action "acquire_wake_lock" with timeout_seconds', () async {
      when(() => mockBackgroundService.acquireWakeLock(
            timeout: any(named: 'timeout'),
          )).thenAnswer((_) async => const Right(true));

      final result = await registry.executeTool('manage_background_service', {
        'action': 'acquire_wake_lock',
        'timeout_seconds': 45,
      });

      expect(result.isRight(), isTrue);
      verify(() => mockBackgroundService.acquireWakeLock(
            timeout: const Duration(seconds: 45),
          )).called(1);
    });

    test('executes action "release_wake_lock"', () async {
      when(() => mockBackgroundService.releaseWakeLock())
          .thenAnswer((_) async => const Right(true));

      final result = await registry.executeTool('manage_background_service', {
        'action': 'release_wake_lock',
      });

      expect(result.isRight(), isTrue);
      verify(() => mockBackgroundService.releaseWakeLock()).called(1);
    });

    test('executes action "toggle_tile_state"', () async {
      when(() => mockBackgroundService.toggleTileState())
          .thenAnswer((_) async => const Right(QuickTileState.active));

      final result = await registry.executeTool('manage_background_service', {
        'action': 'toggle_tile_state',
      });

      expect(result.isRight(), isTrue);
      verify(() => mockBackgroundService.toggleTileState()).called(1);
    });

    test('executes action "update_notification"', () async {
      when(() => mockBackgroundService.updateNotification(
            title: any(named: 'title'),
            content: any(named: 'content'),
          )).thenAnswer((_) async => const Right(true));

      final result = await registry.executeTool('manage_background_service', {
        'action': 'update_notification',
        'title': 'New Title',
        'content': 'New Content',
      });

      expect(result.isRight(), isTrue);
      verify(() => mockBackgroundService.updateNotification(
            title: 'New Title',
            content: 'New Content',
          )).called(1);
    });

    test('executes action "get_tile_state"', () async {
      when(() => mockBackgroundService.getTileState())
          .thenAnswer((_) async => QuickTileState.active);

      final result = await registry.executeTool('manage_background_service', {
        'action': 'get_tile_state',
      });

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => ''), contains('"tile_state":"active"'));
      verify(() => mockBackgroundService.getTileState()).called(1);
    });

    test('executes action "set_tile_state"', () async {
      when(() => mockBackgroundService.setTileState(QuickTileState.active))
          .thenAnswer((_) async => const Right(true));

      final result = await registry.executeTool('manage_background_service', {
        'action': 'set_tile_state',
        'active': true,
      });

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => ''), contains('"tile_state":"active"'));
      verify(() => mockBackgroundService.setTileState(QuickTileState.active)).called(1);
    });

    test('executes action "toggle_tile" alias', () async {
      when(() => mockBackgroundService.toggleTileState())
          .thenAnswer((_) async => const Right(QuickTileState.inactive));

      final result = await registry.executeTool('manage_background_service', {
        'action': 'toggle_tile',
      });

      expect(result.isRight(), isTrue);
      expect(result.getOrElse(() => ''), contains('"tile_state":"inactive"'));
      verify(() => mockBackgroundService.toggleTileState()).called(1);
    });

    test('fails validation when action is missing or unsupported', () async {
      final resMissing =
          await registry.executeTool('manage_background_service', {});
      final resInvalid = await registry.executeTool('manage_background_service', {
        'action': 'invalid_action',
      });

      expect(resMissing.isLeft(), isTrue);
      expect(resInvalid.isLeft(), isTrue);
    });
  });
}
