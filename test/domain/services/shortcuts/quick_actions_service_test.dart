import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:quick_actions/quick_actions.dart';

import 'package:flutter_ai_agent/domain/services/shortcuts/quick_actions_service.dart';

class MockQuickActionsProvider extends Mock implements QuickActionsProvider {}

class MockQuickActions extends Mock implements QuickActions {}

void main() {
  late MockQuickActionsProvider mockProvider;
  late QuickActionsService service;

  setUp(() {
    mockProvider = MockQuickActionsProvider();
    when(() => mockProvider.setShortcutItems(any())).thenAnswer((_) async {});
    when(() => mockProvider.initialize(any())).thenAnswer((_) async {});
    service = QuickActionsService(provider: mockProvider);
  });

  tearDown(() async {
    await service.dispose();
  });

  group('QuickActionsService', () {
    test('constants are correctly configured', () {
      expect(actionVoiceChat, 'action_voice_chat');
      expect(actionAskCamera, 'action_ask_camera');
      expect(actionScanQr, 'action_scan_qr');

      expect(QuickActionsService.actionVoiceChat, 'action_voice_chat');
      expect(QuickActionsService.actionAskCamera, 'action_ask_camera');
      expect(QuickActionsService.actionScanQr, 'action_scan_qr');

      expect(QuickActionsService.defaultShortcuts, hasLength(3));

      final voice = QuickActionsService.defaultShortcuts[0];
      expect(voice.type, 'action_voice_chat');
      expect(voice.localizedTitle, 'Voice Chat');
      expect(voice.icon, 'mic');

      final camera = QuickActionsService.defaultShortcuts[1];
      expect(camera.type, 'action_ask_camera');
      expect(camera.localizedTitle, 'Ask Camera');
      expect(camera.icon, 'camera');

      final qr = QuickActionsService.defaultShortcuts[2];
      expect(qr.type, 'action_scan_qr');
      expect(qr.localizedTitle, 'Scan QR Code');
      expect(qr.icon, 'qr_code');
    });

    test('initialize registers shortcuts and initializes provider callback',
        () async {
      await service.initialize();

      verify(() => mockProvider.setShortcutItems(
            QuickActionsService.defaultShortcuts,
          )).called(1);
      verify(() => mockProvider.initialize(any())).called(1);
    });

    test('invoking onAction callback passed to provider emits on actionStream',
        () async {
      void Function(String)? capturedCallback;

      when(() => mockProvider.initialize(any())).thenAnswer((invocation) async {
        capturedCallback =
            invocation.positionalArguments[0] as void Function(String);
      });

      await service.initialize();
      expect(capturedCallback, isNotNull);

      final expectation = expectLater(
        service.actionStream,
        emitsInOrder([
          'action_voice_chat',
          'action_ask_camera',
          'action_scan_qr',
        ]),
      );

      capturedCallback!('action_voice_chat');
      capturedCallback!('action_ask_camera');
      capturedCallback!('action_scan_qr');

      await expectation;
    });

    test('handleAction pushes items into actionStream', () async {
      final expectation = expectLater(
        service.actionStream,
        emitsInOrder(['custom_action_1', 'custom_action_2']),
      );

      service.handleAction('custom_action_1');
      service.handleAction('custom_action_2');

      await expectation;
    });

    test('handleAction does not throw or emit when controller is closed',
        () async {
      await service.dispose();

      expect(() => service.handleAction('after_dispose'), returnsNormally);
    });

    test('dispose closes the stream controller', () async {
      final expectation = expectLater(
        service.actionStream,
        emitsDone,
      );

      await service.dispose();

      await expectation;
    });
  });

  group('DefaultQuickActionsProvider', () {
    late MockQuickActions mockQuickActions;
    late DefaultQuickActionsProvider provider;

    setUp(() {
      mockQuickActions = MockQuickActions();
      provider = DefaultQuickActionsProvider(quickActions: mockQuickActions);
    });

    test('initialize forwards call to QuickActions instance', () async {
      void testCallback(String type) {}
      when(() => mockQuickActions.initialize(any())).thenAnswer((_) async {});

      await provider.initialize(testCallback);

      verify(() => mockQuickActions.initialize(testCallback)).called(1);
    });

    test('setShortcutItems forwards call to QuickActions instance', () async {
      final items = QuickActionsService.defaultShortcuts;
      when(() => mockQuickActions.setShortcutItems(any()))
          .thenAnswer((_) async {});

      await provider.setShortcutItems(items);

      verify(() => mockQuickActions.setShortcutItems(items)).called(1);
    });
  });
}
