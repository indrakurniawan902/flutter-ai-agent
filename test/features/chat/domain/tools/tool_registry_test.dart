import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
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
}
