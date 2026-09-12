import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/clipboard_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockClipboardService extends Mock implements ClipboardServiceBase {}

class MockLocationService extends Mock implements LocationServiceBase {}

class MockVoiceInputService extends Mock implements VoiceInputServiceBase {}

class MockVoiceOutputService extends Mock implements VoiceOutputServiceBase {}

class MockBackgroundService extends Mock implements BackgroundServiceBase {}

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

      final result = await voiceRegistry.executeTool('speak_text', {
        'text': 'Halo dunia',
        'voice': 'alloy',
      });

      expect(result.isRight(), isTrue);
      verify(
        () => mockVoiceOutputService.speakText('Halo dunia', voice: 'alloy'),
      ).called(1);
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
      ).thenAnswer((_) async => const Right(QuickTileState.active));

      final result = await bgRegistry.executeTool('manage_background_service', {
        'action': 'toggle_tile_state',
      });

      expect(result.isRight(), isTrue);
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
}
