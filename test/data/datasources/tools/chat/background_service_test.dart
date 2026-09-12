import 'package:dartz/dartz.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

void main() {
  late MockBackgroundServicePlatformWrapper mockPlatform;
  late BackgroundService service;
  void Function(String action)? actionHandler;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

  setUp(() {
    mockPlatform = MockBackgroundServicePlatformWrapper();
    actionHandler = null;
    when(
      () => mockPlatform.setActionHandler(any()),
    ).thenAnswer((invocation) {
      actionHandler =
          invocation.positionalArguments[0] as void Function(String)?;
    });
    service = BackgroundService(channel: mockPlatform);
  });

  tearDown(() {
    service.dispose();
  });

  group('BackgroundService - Lifecycle', () {
    test('startService calls platform wrapper and returns Right(true)',
        () async {
      when(
        () => mockPlatform.invokeMethod(
          'startForegroundService',
          any(),
        ),
      ).thenAnswer((_) async => true);

      final result = await service.startService(
        title: 'Flames Active',
        content: 'Listening in background',
      );

      expect(result, const Right<Failure, bool>(true));
      verify(
        () => mockPlatform.invokeMethod(
          'startForegroundService',
          {'title': 'Flames Active', 'content': 'Listening in background'},
        ),
      ).called(1);
    });

    test('startService returns Left(ServerFailure) when wrapper throws',
        () async {
      when(
        () => mockPlatform.invokeMethod(
          'startForegroundService',
          any(),
        ),
      ).thenThrow(Exception('Failed to start service'));

      final result = await service.startService();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('stopService calls platform wrapper and returns Right(true)',
        () async {
      when(
        () => mockPlatform.invokeMethod('stopForegroundService'),
      ).thenAnswer((_) async => true);

      final result = await service.stopService();

      expect(result, const Right<Failure, bool>(true));
      verify(
        () => mockPlatform.invokeMethod('stopForegroundService'),
      ).called(1);
    });

    test('stopService returns Left(ServerFailure) when wrapper throws',
        () async {
      when(
        () => mockPlatform.invokeMethod('stopForegroundService'),
      ).thenThrow(Exception('Stop failed'));

      final result = await service.stopService();

      expect(result.isLeft(), isTrue);
      result.fold(
        (failure) => expect(failure, isA<ServerFailure>()),
        (_) => fail('Expected Left'),
      );
    });

    test('isRunning queries platform wrapper', () async {
      when(
        () => mockPlatform.invokeMethod('isServiceRunning'),
      ).thenAnswer((_) async => true);

      final running = await service.isRunning();

      expect(running, isTrue);
      verify(() => mockPlatform.invokeMethod('isServiceRunning')).called(1);
    });

    test('isRunning returns false on platform wrapper error', () async {
      when(
        () => mockPlatform.invokeMethod('isServiceRunning'),
      ).thenThrow(Exception('Query failed'));

      final running = await service.isRunning();

      expect(running, isFalse);
    });

    test('updateNotification calls platform wrapper with title and content',
        () async {
      when(
        () => mockPlatform.invokeMethod('updateNotification', any()),
      ).thenAnswer((_) async => true);

      final result = await service.updateNotification(
        title: 'Updated Title',
        content: 'Updated Content',
      );

      expect(result, const Right<Failure, bool>(true));
      verify(
        () => mockPlatform.invokeMethod(
          'updateNotification',
          {'title': 'Updated Title', 'content': 'Updated Content'},
        ),
      ).called(1);
    });

    test('updateNotification returns Left(ServerFailure) on exception',
        () async {
      when(
        () => mockPlatform.invokeMethod('updateNotification', any()),
      ).thenThrow(Exception('Update failed'));

      final result = await service.updateNotification(
        title: 'Title',
        content: 'Content',
      );

      expect(result.isLeft(), isTrue);
    });
  });

  group('BackgroundService - Safe WakeLock & Battery Protection', () {
    test('acquireWakeLock clamps timeout to default 30s when omitted',
        () async {
      when(
        () => mockPlatform.invokeMethod('acquireWakeLock', any()),
      ).thenAnswer((_) async => true);

      final result = await service.acquireWakeLock();

      expect(result, const Right<Failure, bool>(true));
      verify(
        () => mockPlatform.invokeMethod('acquireWakeLock', {
          'timeoutMs': 30000,
        }),
      ).called(1);
    });

    test('acquireWakeLock clamps timeout to max 60s to prevent battery drain',
        () async {
      when(
        () => mockPlatform.invokeMethod('acquireWakeLock', any()),
      ).thenAnswer((_) async => true);

      final result = await service.acquireWakeLock(
        timeout: const Duration(seconds: 120),
      );

      expect(result, const Right<Failure, bool>(true));
      verify(
        () => mockPlatform.invokeMethod('acquireWakeLock', {
          'timeoutMs': 60000,
        }),
      ).called(1);
    });

    test('acquireWakeLock clamps timeout to min 1s', () async {
      when(
        () => mockPlatform.invokeMethod('acquireWakeLock', any()),
      ).thenAnswer((_) async => true);

      final result = await service.acquireWakeLock(
        timeout: const Duration(milliseconds: 100),
      );

      expect(result, const Right<Failure, bool>(true));
      verify(
        () => mockPlatform.invokeMethod('acquireWakeLock', {
          'timeoutMs': 1000,
        }),
      ).called(1);
    });

    test('acquireWakeLock returns Left(ServerFailure) on exception', () async {
      when(
        () => mockPlatform.invokeMethod('acquireWakeLock', any()),
      ).thenThrow(Exception('WakeLock acquire failed'));

      final result = await service.acquireWakeLock();

      expect(result.isLeft(), isTrue);
    });

    test('releaseWakeLock calls platform wrapper and returns Right(true)',
        () async {
      when(
        () => mockPlatform.invokeMethod('releaseWakeLock'),
      ).thenAnswer((_) async => true);

      final result = await service.releaseWakeLock();

      expect(result, const Right<Failure, bool>(true));
      verify(() => mockPlatform.invokeMethod('releaseWakeLock')).called(1);
    });

    test('releaseWakeLock returns Left(ServerFailure) on exception', () async {
      when(
        () => mockPlatform.invokeMethod('releaseWakeLock'),
      ).thenThrow(Exception('Release failed'));

      final result = await service.releaseWakeLock();

      expect(result.isLeft(), isTrue);
    });

    test('isWakeLockHeld queries platform wrapper', () async {
      when(
        () => mockPlatform.invokeMethod('isWakeLockHeld'),
      ).thenAnswer((_) async => true);

      final isHeld = await service.isWakeLockHeld();

      expect(isHeld, isTrue);
      verify(() => mockPlatform.invokeMethod('isWakeLockHeld')).called(1);
    });
  });

  group('BackgroundService - Android Quick Settings Tile', () {
    test('getTileState parses active, inactive, and unavailable states',
        () async {
      when(
        () => mockPlatform.invokeMethod('getQuickTileState'),
      ).thenAnswer((_) async => 'active');
      expect(await service.getTileState(), QuickTileState.active);

      when(
        () => mockPlatform.invokeMethod('getQuickTileState'),
      ).thenAnswer((_) async => 'inactive');
      expect(await service.getTileState(), QuickTileState.inactive);

      when(
        () => mockPlatform.invokeMethod('getQuickTileState'),
      ).thenAnswer((_) async => 'unavailable');
      expect(await service.getTileState(), QuickTileState.unavailable);

      when(
        () => mockPlatform.invokeMethod('getQuickTileState'),
      ).thenThrow(Exception('Tile not supported'));
      expect(await service.getTileState(), QuickTileState.unavailable);
    });

    test('setTileState calls platform wrapper with boolean', () async {
      when(
        () => mockPlatform.invokeMethod('setQuickTileState', any()),
      ).thenAnswer((_) async => true);

      final resultActive = await service.setTileState(QuickTileState.active);
      expect(resultActive, const Right<Failure, bool>(true));
      verify(
        () => mockPlatform.invokeMethod('setQuickTileState', {
          'active': true,
        }),
      ).called(1);

      final resultInactive = await service.setTileState(
        QuickTileState.inactive,
      );
      expect(resultInactive, const Right<Failure, bool>(true));
      verify(
        () => mockPlatform.invokeMethod('setQuickTileState', {
          'active': false,
        }),
      ).called(1);
    });

    test('toggleTileState toggles from inactive to active and updates tile',
        () async {
      when(
        () => mockPlatform.invokeMethod('getQuickTileState'),
      ).thenAnswer((_) async => 'inactive');
      when(
        () => mockPlatform.invokeMethod('setQuickTileState', any()),
      ).thenAnswer((_) async => true);

      final result = await service.toggleTileState();

      expect(result, const Right<Failure, QuickTileState>(QuickTileState.active));
      verify(
        () => mockPlatform.invokeMethod('setQuickTileState', {
          'active': true,
        }),
      ).called(1);
    });

    test('toggleTileState toggles from active to inactive and updates tile',
        () async {
      when(
        () => mockPlatform.invokeMethod('getQuickTileState'),
      ).thenAnswer((_) async => 'active');
      when(
        () => mockPlatform.invokeMethod('setQuickTileState', any()),
      ).thenAnswer((_) async => true);

      final result = await service.toggleTileState();

      expect(
        result,
        const Right<Failure, QuickTileState>(QuickTileState.inactive),
      );
      verify(
        () => mockPlatform.invokeMethod('setQuickTileState', {
          'active': false,
        }),
      ).called(1);
    });

    test(
        'toggleTileState maps unavailable to active instead of failing',
        () async {
      when(
        () => mockPlatform.invokeMethod('getQuickTileState'),
      ).thenAnswer((_) async => 'unavailable');
      when(
        () => mockPlatform.invokeMethod('setQuickTileState', any()),
      ).thenAnswer((_) async => true);

      final result = await service.toggleTileState();

      expect(result.isRight(), isTrue);
      result.fold(
        (_) => fail('Expected Right'),
        (state) => expect(state, QuickTileState.active),
      );
    });
  });

  group('BackgroundService - Notification Actions & Inter-Process Events', () {
    test('actionStream emits received actions from platform handler', () async {
      expect(actionHandler, isNotNull);

      final emittedActions = <String>[];
      final sub = service.actionStream.listen(emittedActions.add);

      actionHandler!('voice_input');
      actionHandler!('quick_status');
      await Future<void>.delayed(Duration.zero);

      expect(emittedActions, ['voice_input', 'quick_status']);
      await sub.cancel();
    });

    test('getPendingAction retrieves and clearPendingAction clears', () async {
      when(
        () => mockPlatform.invokeMethod('getPendingAction'),
      ).thenAnswer((_) async => 'voice_input');
      when(
        () => mockPlatform.invokeMethod('clearPendingAction'),
      ).thenAnswer((_) async => null);

      final action = await service.getPendingAction();
      expect(action, 'voice_input');
      verify(() => mockPlatform.invokeMethod('getPendingAction')).called(1);

      await service.clearPendingAction();
      verify(() => mockPlatform.invokeMethod('clearPendingAction')).called(1);
    });

    test('getPendingAction returns null when empty', () async {
      when(
        () => mockPlatform.invokeMethod('getPendingAction'),
      ).thenAnswer((_) async => '');

      expect(await service.getPendingAction(), isNull);
    });
  });
}
