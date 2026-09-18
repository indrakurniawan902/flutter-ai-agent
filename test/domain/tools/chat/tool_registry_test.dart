import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/contact_launcher_tools.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/intent_launcher_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/notification_triage_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/system_settings_allow_list.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
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

class MockVoiceInputService extends Mock implements VoiceInputServiceBase {}

class MockVoiceOutputService extends Mock implements VoiceOutputServiceBase {}

class MockBackgroundService extends Mock implements BackgroundServiceBase {}

class MockContactLauncherTools extends Mock implements ContactLauncherTools {}

class MockIntentLauncherService extends Mock
    implements IntentLauncherServiceBase {}

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

      expect(defs.map((d) => d['function']['name']), contains('sample'));
      expect(defs.first['type'], 'function');
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

    test('register_geofence binds an action when provided', () async {
      // Arrange
      registry.registerAmbientTriggerTools(mockAmbient);

      // Act
      final result = await registry.executeTool('register_geofence', {
        'id': 'g1',
        'latitude': 1.0,
        'longitude': 2.0,
        'action': 'runPrompt',
        'actionPayload': 'Lights on',
        'actionOn': 'enter',
      });

      // Assert
      expect(result.isRight(), isTrue);
      final captured = verify(
        () => mockAmbient.addGeofence(captureAny()),
      ).captured;
      final region = captured.single as GeofenceRegion;
      expect(region.id, 'g1');
      expect(region.action, GeofenceAction.runPrompt);
      expect(region.actionPayload, 'Lights on');
      expect(region.actionOn, GeofenceActionTrigger.enter);
    });

    test('register_geofence defaults to no action when omitted', () async {
      // Arrange
      registry.registerAmbientTriggerTools(mockAmbient);

      // Act
      final result = await registry.executeTool('register_geofence', {
        'id': 'g2',
        'latitude': 1.0,
        'longitude': 2.0,
      });

      // Assert
      expect(result.isRight(), isTrue);
      final captured = verify(
        () => mockAmbient.addGeofence(captureAny()),
      ).captured;
      final region = captured.single as GeofenceRegion;
      expect(region.action, GeofenceAction.none);
      expect(region.actionPayload, isEmpty);
      expect(region.actionOn, GeofenceActionTrigger.both);
    });

    test('register_geofence rejects an unknown action and never registers it',
        () async {
      // Arrange
      registry.registerAmbientTriggerTools(mockAmbient);

      // Act
      final result = await registry.executeTool('register_geofence', {
        'id': 'g3',
        'latitude': 1.0,
        'longitude': 2.0,
        'action': 'speak',
        'actionPayload': 'hi',
      });

      // Assert
      expect(result.isLeft(), isTrue);
      final message = result.fold((failure) => failure.message, (_) => '');
      expect(message, contains('speak'));
      expect(message, contains('runPrompt'));
      verifyNever(() => mockAmbient.addGeofence(any()));
    });

    test('register_geofence rejects a payload-taking action with no payload',
        () async {
      // Arrange
      registry.registerAmbientTriggerTools(mockAmbient);

      // Act
      final runPromptResult = await registry.executeTool('register_geofence', {
        'id': 'g4',
        'latitude': 1.0,
        'longitude': 2.0,
        'action': 'runPrompt',
      });
      final openUrlResult = await registry.executeTool('register_geofence', {
        'id': 'g5',
        'latitude': 1.0,
        'longitude': 2.0,
        'action': 'openUrl',
      });

      // Assert
      expect(runPromptResult.isLeft(), isTrue);
      expect(
        runPromptResult.fold((failure) => failure.message, (_) => ''),
        contains('runPrompt'),
      );
      expect(openUrlResult.isLeft(), isTrue);
      expect(
        openUrlResult.fold((failure) => failure.message, (_) => ''),
        contains('openUrl'),
      );
      verifyNever(() => mockAmbient.addGeofence(any()));
    });

    test('register_geofence round-trips every allowed action', () async {
      // Arrange
      registry.registerAmbientTriggerTools(mockAmbient);
      final payloads = <String, String>{
        'none': '',
        'notify': '',
        'runPrompt': 'Lights on',
        'openUrl': 'https://example.com',
      };

      // Act & Assert
      for (final name in geofenceActionNames) {
        clearInteractions(mockAmbient);
        final result = await registry.executeTool('register_geofence', {
          'id': 'g_$name',
          'latitude': 1.0,
          'longitude': 2.0,
          'action': name,
          'actionPayload': payloads[name],
        });

        expect(result.isRight(), isTrue, reason: 'action $name rejected');
        final captured = verify(
          () => mockAmbient.addGeofence(captureAny()),
        ).captured;
        final region = captured.single as GeofenceRegion;
        expect(geofenceActionToJson(region.action), name);
        expect(region.actionPayload, payloads[name]);
      }
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

    test(
        'executes listen_voice_input and returns transcribed text on permission grant',
        () async {
      when(
        () => mockVoiceService.checkPermission(),
      ).thenAnswer((_) async => const Right(true));
      when(
        () => mockVoiceService.statusStream,
      ).thenAnswer((_) => Stream.value(VoiceInputStatus.done));
      when(
        () => mockVoiceService.startListening(
          listenFor: any(named: 'listenFor'),
        ),
      ).thenAnswer((_) async => const Right(unit));
      when(
        () => mockVoiceService.stopListening(),
      ).thenAnswer((_) async => const Right('Halo Hermit'));

      final result = await registry.executeTool('listen_voice_input', {
        'listenDurationSeconds': 5,
      });

      expect(result, const Right<Failure, String>('Halo Hermit'));
      verify(
        () => mockVoiceService.startListening(
          listenFor: const Duration(seconds: 5),
        ),
      ).called(1);
      verify(() => mockVoiceService.stopListening()).called(1);
    });

    test('denies listen_voice_input when permission is denied', () async {
      when(
        () => mockVoiceService.checkPermission(),
      ).thenAnswer(
        (_) async => const Left(PermissionFailure('Mic access denied')),
      );

      final result = await registry.executeTool('listen_voice_input', {});

      expect(
        result,
        const Left<Failure, String>(
          PermissionFailure('Permission denied for tool: listen_voice_input'),
        ),
      );
      verifyNever(
        () => mockVoiceService.startListening(
          listenFor: any(named: 'listenFor'),
        ),
      );
    });
  });

  group('ToolRegistry - Voice Output Tools', () {
    late ToolRegistry voiceRegistry;
    late MockVoiceOutputService mockVoiceOutputService;

    setUp(() {
      voiceRegistry = ToolRegistry();
      mockVoiceOutputService = MockVoiceOutputService();
      voiceRegistry.registerVoiceOutputTools(mockVoiceOutputService);
    });

    test('registers speak_text as tier1 auto tool', () {
      expect(voiceRegistry.hasTool('speak_text'), isTrue);
      expect(
        voiceRegistry.getTool('speak_text')?.securityTier,
        equals(SecurityTier.tier1Auto),
      );
    });

    test('executes speak_text and delegates to voiceOutputService.speakText',
        () async {
      when(
        () => mockVoiceOutputService.speakText(
          'Halo dunia',
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer((_) async => const Right(unit));
      when(() => mockVoiceOutputService.lastEngineUsed)
          .thenReturn(TtsEngine.androidTts);

      final result = await voiceRegistry.executeTool('speak_text', {
        'text': 'Halo dunia',
        'voice': 'alloy',
      });

      expect(result.isRight(), isTrue);
      verify(
        () => mockVoiceOutputService.speakText('Halo dunia', voice: 'alloy'),
      ).called(1);
      final json =
          jsonDecode(result.getOrElse(() => '{}')) as Map<String, dynamic>;
      expect(json['engine'], 'android_tts');
    });

    test('fails validation when text parameter is empty or missing', () async {
      final resultMissing = await voiceRegistry.executeTool('speak_text', {});
      final resultEmpty = await voiceRegistry.executeTool('speak_text', {
        'text': '   ',
      });

      expect(resultMissing.isLeft(), isTrue);
      expect(resultEmpty.isLeft(), isTrue);
      resultMissing.fold(
        (failure) => expect(failure, isA<ValidationFailure>()),
        (_) => fail('Expected Left(ValidationFailure)'),
      );
    });

    test('returns Left(Failure) when voiceOutputService.speakText fails',
        () async {
      when(
        () => mockVoiceOutputService.speakText(
          any(),
          voice: any(named: 'voice'),
          model: any(named: 'model'),
          speed: any(named: 'speed'),
        ),
      ).thenAnswer(
        (_) async => const Left(ServerFailure('TTS service error')),
      );

      final result = await voiceRegistry.executeTool('speak_text', {
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
    late ToolRegistry bgRegistry;
    late MockBackgroundService mockBackgroundService;

    setUp(() {
      bgRegistry = ToolRegistry();
      mockBackgroundService = MockBackgroundService();
      bgRegistry.registerBackgroundServiceTools(mockBackgroundService);
    });

    test('registers manage_background_service as tier1 auto tool', () {
      expect(bgRegistry.hasTool('manage_background_service'), isTrue);
      expect(
        bgRegistry.getTool('manage_background_service')?.securityTier,
        equals(SecurityTier.tier1Auto),
      );
    });

    test('executes action "start" and delegates to startService', () async {
      when(
        () => mockBackgroundService.startService(
          title: any(named: 'title'),
          content: any(named: 'content'),
        ),
      ).thenAnswer((_) async => const Right(true));

      final result = await bgRegistry.executeTool('manage_background_service', {
        'action': 'start',
        'title': 'Agent Active',
        'content': 'Running task in background',
      });

      expect(result.isRight(), isTrue);
      verify(
        () => mockBackgroundService.startService(
          title: 'Agent Active',
          content: 'Running task in background',
        ),
      ).called(1);
    });

    test('executes action "stop" and delegates to stopService', () async {
      when(
        () => mockBackgroundService.stopService(),
      ).thenAnswer((_) async => const Right(true));

      final result = await bgRegistry.executeTool('manage_background_service', {
        'action': 'stop',
      });

      expect(result.isRight(), isTrue);
      verify(() => mockBackgroundService.stopService()).called(1);
    });

    test('executes action "status" and returns service and wakelock state',
        () async {
      when(
        () => mockBackgroundService.isRunning(),
      ).thenAnswer((_) async => true);
      when(
        () => mockBackgroundService.isWakeLockHeld(),
      ).thenAnswer((_) async => false);
      when(
        () => mockBackgroundService.getTileState(),
      ).thenAnswer((_) async => QuickTileState.active);

      final result = await bgRegistry.executeTool('manage_background_service', {
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
      when(
        () => mockBackgroundService.acquireWakeLock(
          timeout: any(named: 'timeout'),
        ),
      ).thenAnswer((_) async => const Right(true));

      final result = await bgRegistry.executeTool('manage_background_service', {
        'action': 'acquire_wake_lock',
        'timeout_seconds': 45,
      });

      expect(result.isRight(), isTrue);
      verify(
        () => mockBackgroundService.acquireWakeLock(
          timeout: const Duration(seconds: 45),
        ),
      ).called(1);
    });

    test('executes action "release_wake_lock"', () async {
      when(
        () => mockBackgroundService.releaseWakeLock(),
      ).thenAnswer((_) async => const Right(true));

      final result = await bgRegistry.executeTool('manage_background_service', {
        'action': 'release_wake_lock',
      });

      expect(result.isRight(), isTrue);
      verify(() => mockBackgroundService.releaseWakeLock()).called(1);
    });

    test('executes action "toggle_tile_state"', () async {
      when(
        () => mockBackgroundService.toggleTileState(),
      ).thenAnswer(
        (_) async => const Right(TileStateChange(
          state: QuickTileState.active,
          changed: true,
          reason: 'toggled',
        )),
      );

      final result = await bgRegistry.executeTool('manage_background_service', {
        'action': 'toggle_tile_state',
      });

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (text) {
          expect(text, contains('"status":"tile_state_toggled"'));
          expect(text, contains('"tile_state":"active"'));
        },
      );
      verify(() => mockBackgroundService.toggleTileState()).called(1);
    });

    test('reports tile_state_unchanged when the toggle did not take', () async {
      when(
        () => mockBackgroundService.toggleTileState(),
      ).thenAnswer(
        (_) async => const Right(TileStateChange(
          state: QuickTileState.inactive,
          changed: false,
          reason: 'state_unchanged',
        )),
      );

      final result = await bgRegistry.executeTool('manage_background_service', {
        'action': 'toggle_tile_state',
      });

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (text) {
          expect(text, contains('"status":"tile_state_unchanged"'));
          expect(text, contains('"tile_state":"inactive"'));
          expect(text, contains('"reason":"state_unchanged"'));
        },
      );
      verify(() => mockBackgroundService.toggleTileState()).called(1);
    });

    test('fails validation when action is missing or unsupported', () async {
      final resMissing = await bgRegistry.executeTool(
        'manage_background_service',
        {},
      );
      final resInvalid = await bgRegistry.executeTool(
        'manage_background_service',
        {'action': 'invalid_action'},
      );

      expect(resMissing.isLeft(), isTrue);
      expect(resInvalid.isLeft(), isTrue);
    });
  });

  group('registerContactLauncherTools', () {
    late MockContactLauncherTools mockContactLauncher;

    setUp(() {
      mockContactLauncher = MockContactLauncherTools();
    });

    test(
        'registers search_contacts, open_whatsapp_chat, and open_external_url',
        () {
      registry.registerContactLauncherTools(mockContactLauncher);

      expect(registry.hasTool('search_contacts'), isTrue);
      expect(registry.hasTool('open_whatsapp_chat'), isTrue);
      expect(registry.hasTool('open_external_url'), isTrue);

      expect(
        registry.getTool('search_contacts')?.securityTier,
        SecurityTier.tier2Permission,
      );
      expect(
        registry.getTool('open_whatsapp_chat')?.securityTier,
        SecurityTier.tier3Hitl,
      );
      expect(
        registry.getTool('open_external_url')?.securityTier,
        SecurityTier.tier2Permission,
      );

      final searchParams = registry.getTool('search_contacts')?.parameters;
      expect(searchParams?['type'], 'object');
      expect(searchParams?['required'], contains('query'));

      final waParams = registry.getTool('open_whatsapp_chat')?.parameters;
      expect(waParams?['type'], 'object');
      expect(waParams?['required'], contains('phone'));

      final urlParams = registry.getTool('open_external_url')?.parameters;
      expect(urlParams?['type'], 'object');
      expect(urlParams?['required'], contains('url'));
    });

    test('search_contacts delegates execution when permission granted',
        () async {
      when(() => mockContactLauncher.checkContactsPermission())
          .thenAnswer((_) async => true);
      when(() => mockContactLauncher.searchContacts('Alice'))
          .thenAnswer((_) async => const Right('[{"displayName":"Alice"}]'));

      registry.registerContactLauncherTools(mockContactLauncher);

      final result =
          await registry.executeTool('search_contacts', {'query': 'Alice'});

      expect(result, const Right<Failure, String>('[{"displayName":"Alice"}]'));
      verify(() => mockContactLauncher.checkContactsPermission()).called(1);
      verify(() => mockContactLauncher.searchContacts('Alice')).called(1);
    });

    test('search_contacts returns PermissionFailure when permission denied',
        () async {
      when(() => mockContactLauncher.checkContactsPermission())
          .thenAnswer((_) async => false);

      registry.registerContactLauncherTools(mockContactLauncher);

      final result =
          await registry.executeTool('search_contacts', {'query': 'Alice'});

      expect(
        result,
        const Left<Failure, String>(
          PermissionFailure('Permission denied for tool: search_contacts'),
        ),
      );
      verify(() => mockContactLauncher.checkContactsPermission()).called(1);
      verifyNever(() => mockContactLauncher.searchContacts(any()));
    });

    test('open_whatsapp_chat delegates execution', () async {
      when(
        () => mockContactLauncher.openWhatsappChat(
          '1234567890',
          message: 'Hello!',
        ),
      ).thenAnswer(
          (_) async => const Right('WhatsApp chat opened for 1234567890'));

      registry.registerContactLauncherTools(mockContactLauncher);

      final result = await registry.executeTool('open_whatsapp_chat', {
        'phone': '1234567890',
        'message': 'Hello!',
      });

      expect(
        result,
        const Right<Failure, String>('WhatsApp chat opened for 1234567890'),
      );
      verify(
        () => mockContactLauncher.openWhatsappChat(
          '1234567890',
          message: 'Hello!',
        ),
      ).called(1);
    });

    test('open_external_url delegates execution', () async {
      when(() => mockContactLauncher.openExternalUrl('https://example.com'))
          .thenAnswer(
              (_) async => const Right('Opened URL: https://example.com'));

      registry.registerContactLauncherTools(mockContactLauncher);

      final result = await registry.executeTool('open_external_url', {
        'url': 'https://example.com',
      });

      expect(
        result,
        const Right<Failure, String>('Opened URL: https://example.com'),
      );
      verify(() => mockContactLauncher.openExternalUrl('https://example.com'))
          .called(1);
    });
  });

  group('registerIntentLauncherTools', () {
    late MockIntentLauncherService mockIntentLauncher;

    setUp(() {
      mockIntentLauncher = MockIntentLauncherService();
    });

    test(
        'registers open_map_navigation, open_email_composer, '
        'and launch_system_setting', () {
      registry.registerIntentLauncherTools(mockIntentLauncher);

      expect(registry.hasTool('open_map_navigation'), isTrue);
      expect(registry.hasTool('open_email_composer'), isTrue);
      expect(registry.hasTool('launch_system_setting'), isTrue);

      expect(
        registry.getTool('open_map_navigation')?.securityTier,
        SecurityTier.tier1Auto,
      );
      expect(
        registry.getTool('open_email_composer')?.securityTier,
        SecurityTier.tier2Permission,
      );
      expect(
        registry.getTool('launch_system_setting')?.securityTier,
        SecurityTier.tier2Permission,
      );

      final mapParams = registry.getTool('open_map_navigation')?.parameters;
      expect(mapParams?['type'], 'object');
      expect(mapParams?['properties']?.keys,
          containsAll(['latitude', 'longitude', 'query']));
      expect(mapParams?.containsKey('required'), isFalse);

      final emailParams = registry.getTool('open_email_composer')?.parameters;
      expect(emailParams?['properties']?.keys,
          containsAll(['to', 'subject', 'body']));
      expect(emailParams?.containsKey('required'), isFalse);

      final settingParams = registry.getTool('launch_system_setting')?.parameters;
      expect(settingParams?['properties']?.keys, contains('setting_type'));
      expect(settingParams?['required'], ['setting_type']);
      // T18.2: an LLM must not have to guess the allowed values, and the §7
      // special-permission CTAs must be advertised.
      final settingTypeProperty =
          settingParams?['properties']?['setting_type'] as Map?;
      expect(
        settingTypeProperty?['enum'],
        SystemSettingsAllowList.values,
      );
      expect(
        settingTypeProperty?['enum'],
        containsAll(<String>['notification_listener', 'nfc', 'app_details']),
      );
      expect(
        settingTypeProperty?['enum'],
        containsAll(<String>['accessibility', 'overlay']),
      );
      expect(
        settingTypeProperty?['description']?.toString(),
        contains('notification_listener'),
      );
      final settingDescription =
          registry.getTool('launch_system_setting')?.description ?? '';
      expect(settingDescription, contains('app_details'));
      expect(settingDescription, contains('accessibility'));
      expect(settingDescription, contains('overlay'));
      expect(settingDescription, contains('display over other apps'));
    });

    test('open_map_navigation delegates typed coordinates', () async {
      when(
        () => mockIntentLauncher.openMapNavigation(
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
          query: any(named: 'query'),
        ),
      ).thenAnswer((_) async => const Right('ok'));

      registry.registerIntentLauncherTools(mockIntentLauncher);

      final result = await registry.executeTool('open_map_navigation', {
        'latitude': -6.2,
        'longitude': 106.8,
      });

      expect(result, const Right<Failure, String>('ok'));
      verify(
        () => mockIntentLauncher.openMapNavigation(
          latitude: -6.2,
          longitude: 106.8,
          query: null,
        ),
      ).called(1);
    });

    test('open_email_composer delegates optional fields', () async {
      when(
        () => mockIntentLauncher.openEmailComposer(
          to: any(named: 'to'),
          subject: any(named: 'subject'),
          body: any(named: 'body'),
        ),
      ).thenAnswer((_) async => const Right('ok'));

      registry.registerIntentLauncherTools(mockIntentLauncher);

      final result = await registry.executeTool('open_email_composer', {
        'to': 'dev@example.com',
        'subject': 'Hi',
      });

      expect(result, const Right<Failure, String>('ok'));
      verify(
        () => mockIntentLauncher.openEmailComposer(
          to: 'dev@example.com',
          subject: 'Hi',
          body: null,
        ),
      ).called(1);
    });

    test('launch_system_setting delegates setting type', () async {
      when(() => mockIntentLauncher.launchSystemSetting(any()))
          .thenAnswer((_) async => const Right('ok'));

      registry.registerIntentLauncherTools(mockIntentLauncher);

      final result = await registry.executeTool(
        'launch_system_setting',
        {'setting_type': 'wifi'},
      );

      expect(result, const Right<Failure, String>('ok'));
      verify(() => mockIntentLauncher.launchSystemSetting('wifi')).called(1);
    });

    test('constructor auto-registers intent launcher tools', () {
      final intentRegistry = ToolRegistry(
        intentLauncherService: MockIntentLauncherService(),
      );

      expect(intentRegistry.hasTool('open_map_navigation'), isTrue);
      expect(intentRegistry.hasTool('open_email_composer'), isTrue);
      expect(intentRegistry.hasTool('launch_system_setting'), isTrue);
    });
  });

  group('tool enable/disable state', () {
    test('newly registered tools are enabled by default', () {
      registry.register(sampleTool());

      expect(registry.isToolEnabled('sample'), isTrue);
      expect(registry.activeTools.map((t) => t.name), contains('sample'));
    });

    test('unknown tools default to enabled', () {
      expect(registry.isToolEnabled('never_registered'), isTrue);
    });

    test('disabled tools are excluded from definitions and activeTools',
        () async {
      registry.register(sampleTool());
      registry.setToolEnabled('sample', false);

      expect(registry.isToolEnabled('sample'), isFalse);
      expect(registry.activeTools.map((t) => t.name),
          isNot(contains('sample')));
      expect(
        registry.getOpenAiToolDefinitions().map((d) => d['function']['name']),
        isNot(contains('sample')),
      );

      registry.setToolEnabled('sample', true);

      expect(registry.isToolEnabled('sample'), isTrue);
      expect(
        registry.getOpenAiToolDefinitions().map((d) => d['function']['name']),
        contains('sample'),
      );
    });

    test('executeTool rejects disabled tools with ServerFailure', () async {
      registry.register(sampleTool());
      registry.setToolEnabled('sample', false);

      final result = await registry.executeTool('sample');

      expect(
        result,
        const Left<Failure, String>(
          ServerFailure('Tool sample is disabled by skill policy.'),
        ),
      );
    });

    test('tool_search does not enumerate tools disabled by skill policy',
        () async {
      registry.register(sampleTool());
      registry.setToolEnabled('sample', false);

      final result =
          await registry.executeTool('tool_search', {'query': 'sample'});

      expect(result.isRight(), isTrue);
      // Disabled tool must not be enumerated, so its listing line is absent.
      expect(result.getOrElse(() => ''), isNot(contains('sample tool')));
    });

    test('unregister removes tool and its enabled state', () {
      registry.register(sampleTool());
      registry.setToolEnabled('sample', false);
      registry.unregister('sample');

      expect(registry.hasTool('sample'), isFalse);
      expect(registry.isToolEnabled('sample'), isTrue);
    });

    test('constructor auto-registers contact launcher tools', () {
      final contactRegistry = ToolRegistry(
        contactLauncherTools: MockContactLauncherTools(),
      );

      expect(contactRegistry.hasTool('search_contacts'), isTrue);
      expect(contactRegistry.hasTool('open_whatsapp_chat'), isTrue);
      expect(contactRegistry.hasTool('open_external_url'), isTrue);
    });
  });
}
