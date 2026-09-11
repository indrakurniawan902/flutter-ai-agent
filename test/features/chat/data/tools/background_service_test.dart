import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';
import 'package:flutter_ai_agent/features/chat/data/tools/background_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockBackgroundServicePlatformWrapper extends Mock
    implements BackgroundServicePlatformWrapper {}

void main() {
  late MockBackgroundServicePlatformWrapper mockPlatform;
  late BackgroundService service;
  late StreamController<String> actionStreamController;

  setUp(() {
    mockPlatform = MockBackgroundServicePlatformWrapper();
    actionStreamController = StreamController<String>.broadcast();
    when(() => mockPlatform.actionStream)
        .thenAnswer((_) => actionStreamController.stream);
    service = BackgroundService(platformWrapper: mockPlatform);
  });

  tearDown(() {
    actionStreamController.close();
    service.dispose();
  });

  group('BackgroundService - Lifecycle', () {
    test('startService calls platform wrapper and returns Right(true) on success',
        () async {
      when(() => mockPlatform.startForegroundService(
            title: any(named: 'title'),
            content: any(named: 'content'),
          )).thenAnswer((_) async => true);

      final result = await service.startService(
        title: 'Flames Active',
        content: 'Listening in background',
      );

      expect(result, const Right(true));
      verify(() => mockPlatform.startForegroundService(
            title: 'Flames Active',
            content: 'Listening in background',
          )).called(1);
    });

    test('startService returns Left(ServerFailure) when platform wrapper throws',
        () async {
      when(() => mockPlatform.startForegroundService(
            title: any(named: 'title'),
            content: any(named: 'content'),
          )).thenThrow(Exception('Failed to start service'));

      final result = await service.startService();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('stopService calls platform wrapper and returns Right(true)', () async {
      when(() => mockPlatform.stopForegroundService())
          .thenAnswer((_) async => true);

      final result = await service.stopService();

      expect(result, const Right(true));
      verify(() => mockPlatform.stopForegroundService()).called(1);
    });

    test('stopService returns Left(ServerFailure) when platform wrapper throws',
        () async {
      when(() => mockPlatform.stopForegroundService())
          .thenThrow(Exception('Stop failed'));

      final result = await service.stopService();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('isRunning queries platform wrapper', () async {
      when(() => mockPlatform.isServiceRunning()).thenAnswer((_) async => true);

      final running = await service.isRunning();

      expect(running, isTrue);
      verify(() => mockPlatform.isServiceRunning()).called(1);
    });

    test('isRunning returns false on platform wrapper error', () async {
      when(() => mockPlatform.isServiceRunning())
          .thenThrow(Exception('Query failed'));

      final running = await service.isRunning();

      expect(running, isFalse);
    });

    test('updateNotification calls platform wrapper with title and content',
        () async {
      when(() => mockPlatform.updateNotification(
            title: any(named: 'title'),
            content: any(named: 'content'),
          )).thenAnswer((_) async => true);

      final result = await service.updateNotification(
        title: 'Updated Title',
        content: 'Updated Content',
      );

      expect(result, const Right(true));
      verify(() => mockPlatform.updateNotification(
            title: 'Updated Title',
            content: 'Updated Content',
          )).called(1);
    });

    test('updateNotification returns Left(ServerFailure) on exception',
        () async {
      when(() => mockPlatform.updateNotification(
            title: any(named: 'title'),
            content: any(named: 'content'),
          )).thenThrow(Exception('Update failed'));

      final result = await service.updateNotification(
        title: 'Title',
        content: 'Content',
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('BackgroundService - Safe WakeLock & Battery Protection', () {
    test('acquireWakeLock clamps timeout to default 30s when omitted', () async {
      when(() => mockPlatform.acquireWakeLock(
            timeoutMs: any(named: 'timeoutMs'),
          )).thenAnswer((_) async => true);

      final result = await service.acquireWakeLock();

      expect(result, const Right(true));
      verify(() => mockPlatform.acquireWakeLock(timeoutMs: 30000)).called(1);
    });

    test('acquireWakeLock clamps timeout to max 60s to prevent battery drain',
        () async {
      when(() => mockPlatform.acquireWakeLock(
            timeoutMs: any(named: 'timeoutMs'),
          )).thenAnswer((_) async => true);

      // Pass 120s (exceeds 60s max)
      final result = await service.acquireWakeLock(
        timeout: const Duration(seconds: 120),
      );

      expect(result, const Right(true));
      // Must be clamped to 60000 ms
      verify(() => mockPlatform.acquireWakeLock(timeoutMs: 60000)).called(1);
    });

    test('acquireWakeLock clamps timeout to min 1s', () async {
      when(() => mockPlatform.acquireWakeLock(
            timeoutMs: any(named: 'timeoutMs'),
          )).thenAnswer((_) async => true);

      // Pass 100ms (below 1s min)
      final result = await service.acquireWakeLock(
        timeout: const Duration(milliseconds: 100),
      );

      expect(result, const Right(true));
      verify(() => mockPlatform.acquireWakeLock(timeoutMs: 1000)).called(1);
    });

    test('acquireWakeLock returns Left(ServerFailure) on exception', () async {
      when(() => mockPlatform.acquireWakeLock(
            timeoutMs: any(named: 'timeoutMs'),
          )).thenThrow(Exception('WakeLock acquire failed'));

      final result = await service.acquireWakeLock();

      expect(result.isLeft(), isTrue);
    });

    test('releaseWakeLock calls platform wrapper and returns Right(true)',
        () async {
      when(() => mockPlatform.releaseWakeLock()).thenAnswer((_) async => true);

      final result = await service.releaseWakeLock();

      expect(result, const Right(true));
      verify(() => mockPlatform.releaseWakeLock()).called(1);
    });

    test('releaseWakeLock returns Left(ServerFailure) on exception', () async {
      when(() => mockPlatform.releaseWakeLock())
          .thenThrow(Exception('Release failed'));

      final result = await service.releaseWakeLock();

      expect(result.isLeft(), isTrue);
    });

    test('isWakeLockHeld queries platform wrapper', () async {
      when(() => mockPlatform.isWakeLockHeld()).thenAnswer((_) async => true);

      final isHeld = await service.isWakeLockHeld();

      expect(isHeld, isTrue);
      verify(() => mockPlatform.isWakeLockHeld()).called(1);
    });
  });

  group('BackgroundService - Android Quick Settings Tile', () {
    test('getTileState parses active, inactive, and unavailable states',
        () async {
      when(() => mockPlatform.getQuickTileState())
          .thenAnswer((_) async => 'active');
      expect(await service.getTileState(), QuickTileState.active);

      when(() => mockPlatform.getQuickTileState())
          .thenAnswer((_) async => 'inactive');
      expect(await service.getTileState(), QuickTileState.inactive);

      when(() => mockPlatform.getQuickTileState())
          .thenAnswer((_) async => 'unavailable');
      expect(await service.getTileState(), QuickTileState.unavailable);

      when(() => mockPlatform.getQuickTileState())
          .thenThrow(Exception('Tile not supported'));
      expect(await service.getTileState(), QuickTileState.unavailable);
    });

    test('setTileState calls platform wrapper with boolean', () async {
      when(() => mockPlatform.setQuickTileState(any()))
          .thenAnswer((_) async => true);

      final resultActive = await service.setTileState(QuickTileState.active);
      expect(resultActive, const Right(true));
      verify(() => mockPlatform.setQuickTileState(true)).called(1);

      final resultInactive = await service.setTileState(QuickTileState.inactive);
      expect(resultInactive, const Right(true));
      verify(() => mockPlatform.setQuickTileState(false)).called(1);
    });

    test('toggleTileState toggles from inactive to active and updates tile',
        () async {
      when(() => mockPlatform.getQuickTileState())
          .thenAnswer((_) async => 'inactive');
      when(() => mockPlatform.setQuickTileState(true))
          .thenAnswer((_) async => true);

      final result = await service.toggleTileState();

      expect(result, const Right(QuickTileState.active));
      verify(() => mockPlatform.setQuickTileState(true)).called(1);
    });

    test('toggleTileState toggles from active to inactive and updates tile',
        () async {
      when(() => mockPlatform.getQuickTileState())
          .thenAnswer((_) async => 'active');
      when(() => mockPlatform.setQuickTileState(false))
          .thenAnswer((_) async => true);

      final result = await service.toggleTileState();

      expect(result, const Right(QuickTileState.inactive));
      verify(() => mockPlatform.setQuickTileState(false)).called(1);
    });

    test('toggleTileState returns Left(ServerFailure) when unavailable',
        () async {
      when(() => mockPlatform.getQuickTileState())
          .thenAnswer((_) async => 'unavailable');

      final result = await service.toggleTileState();

      expect(result.isLeft(), isTrue);
      result.fold(
        (f) => expect(f.message, contains('Quick Settings Tile unavailable')),
        (_) => fail('Expected Left'),
      );
    });
  });

  group('BackgroundService - Notification Actions & Inter-Process Events', () {
    test('actionStream emits received actions from platform wrapper', () async {
      final emittedActions = <String>[];
      final sub = service.actionStream.listen(emittedActions.add);

      actionStreamController.add('voice_input');
      actionStreamController.add('quick_status');
      await Future<void>.delayed(Duration.zero);

      expect(emittedActions, ['voice_input', 'quick_status']);
      await sub.cancel();
    });

    test('getPendingAction retrieves and clearPendingAction clears pending action',
        () async {
      when(() => mockPlatform.getPendingAction())
          .thenAnswer((_) async => 'voice_input');
      when(() => mockPlatform.clearPendingAction())
          .thenAnswer((_) async => true);

      final action = await service.getPendingAction();
      expect(action, 'voice_input');
      verify(() => mockPlatform.getPendingAction()).called(1);

      await service.clearPendingAction();
      verify(() => mockPlatform.clearPendingAction()).called(1);
    });
  });
}
