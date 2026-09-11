import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/core/errors/failures.dart';

/// States for the Android Quick Settings Tile.
enum QuickTileState {
  active,
  inactive,
  unavailable,
}

/// Abstract platform wrapper for Android background service & Quick Settings Tile.
abstract class BackgroundServicePlatformWrapper {
  Future<bool> startForegroundService({String? title, String? content});
  Future<bool> stopForegroundService();
  Future<bool> isServiceRunning();
  Future<bool> updateNotification({
    required String title,
    required String content,
  });
  Future<bool> acquireWakeLock({int timeoutMs = 30000});
  Future<bool> releaseWakeLock();
  Future<bool> isWakeLockHeld();
  Future<String> getQuickTileState();
  Future<bool> setQuickTileState(bool active);
  Future<String?> getPendingAction();
  Future<bool> clearPendingAction();
  Stream<String> get actionStream;
}

/// Default implementation of [BackgroundServicePlatformWrapper] using [MethodChannel].
class DefaultBackgroundServicePlatformWrapper
    implements BackgroundServicePlatformWrapper {
  static const _channel = MethodChannel('ai.hermes.flames/background_service');
  final StreamController<String> _actionController =
      StreamController<String>.broadcast();

  DefaultBackgroundServicePlatformWrapper() {
    _channel.setMethodCallHandler(_handlePlatformCall);
  }

  Future<dynamic> _handlePlatformCall(MethodCall call) async {
    if (call.method == 'onActionReceived') {
      final action = call.arguments?.toString();
      if (action != null && action.isNotEmpty) {
        _actionController.add(action);
      }
    }
  }

  @override
  Stream<String> get actionStream => _actionController.stream;

  @override
  Future<bool> startForegroundService({String? title, String? content}) async {
    try {
      final payload = <String, dynamic>{};
      if (title != null) payload['title'] = title;
      if (content != null) payload['content'] = content;
      final res =
          await _channel.invokeMethod<bool>('startForegroundService', payload);
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> stopForegroundService() async {
    try {
      final res = await _channel.invokeMethod<bool>('stopForegroundService');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isServiceRunning() async {
    try {
      final res = await _channel.invokeMethod<bool>('isServiceRunning');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> updateNotification({
    required String title,
    required String content,
  }) async {
    try {
      final res = await _channel.invokeMethod<bool>('updateNotification', {
        'title': title,
        'content': content,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> acquireWakeLock({int timeoutMs = 30000}) async {
    try {
      final res = await _channel.invokeMethod<bool>('acquireWakeLock', {
        'timeoutMs': timeoutMs,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> releaseWakeLock() async {
    try {
      final res = await _channel.invokeMethod<bool>('releaseWakeLock');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isWakeLockHeld() async {
    try {
      final res = await _channel.invokeMethod<bool>('isWakeLockHeld');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String> getQuickTileState() async {
    try {
      final res = await _channel.invokeMethod<String>('getQuickTileState');
      return res ?? 'unavailable';
    } catch (_) {
      return 'unavailable';
    }
  }

  @override
  Future<bool> setQuickTileState(bool active) async {
    try {
      final res = await _channel.invokeMethod<bool>('setQuickTileState', {
        'active': active,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> getPendingAction() async {
    try {
      return await _channel.invokeMethod<String>('getPendingAction');
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> clearPendingAction() async {
    try {
      final res = await _channel.invokeMethod<bool>('clearPendingAction');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Base contract for background service operations, Quick Settings Tile, and safe WakeLock.
abstract class BackgroundServiceBase {
  /// Starts the Android foreground service with persistent notification and action buttons.
  Future<Either<Failure, bool>> startService({String? title, String? content});

  /// Stops the foreground service.
  Future<Either<Failure, bool>> stopService();

  /// Queries whether the background service is actively running.
  Future<bool> isRunning();

  /// Updates the foreground notification title and content dynamically.
  Future<Either<Failure, bool>> updateNotification({
    required String title,
    required String content,
  });

  /// Safely acquires a wake-lock with bounded timeout (default 30s, capped at 60s)
  /// to keep the CPU awake during critical agent execution without killing battery.
  Future<Either<Failure, bool>> acquireWakeLock({Duration? timeout});

  /// Releases the wake-lock if currently held.
  Future<Either<Failure, bool>> releaseWakeLock();

  /// Queries whether the wake-lock is currently held.
  Future<bool> isWakeLockHeld();

  /// Gets the current state of the Android Quick Settings Tile.
  Future<QuickTileState> getTileState();

  /// Sets the Quick Settings Tile state (active or inactive).
  Future<Either<Failure, bool>> setTileState(QuickTileState state);

  /// Toggles the Quick Settings Tile between active and inactive.
  Future<Either<Failure, QuickTileState>> toggleTileState();

  /// Stream of actions triggered from Quick Settings Tile or Foreground notification buttons.
  Stream<String> get actionStream;

  /// Retrieves any pending action passed via launch intent (e.g. 'voice_input', 'quick_status').
  Future<String?> getPendingAction();

  /// Clears pending action once consumed.
  Future<void> clearPendingAction();

  /// Disposes resources and listeners.
  void dispose();
}

/// Concrete implementation of [BackgroundServiceBase].
class BackgroundService implements BackgroundServiceBase {
  final BackgroundServicePlatformWrapper _platformWrapper;
  StreamSubscription<String>? _actionSubscription;
  final StreamController<String> _actionController =
      StreamController<String>.broadcast();

  // Safe battery constraints for WakeLock
  static const int minWakeLockTimeoutMs = 1000; // 1s
  static const int defaultWakeLockTimeoutMs = 30000; // 30s
  static const int maxWakeLockTimeoutMs = 60000; // 60s max to prevent battery drain

  BackgroundService({
    BackgroundServicePlatformWrapper? platformWrapper,
  }) : _platformWrapper =
            platformWrapper ?? DefaultBackgroundServicePlatformWrapper() {
    _actionSubscription = _platformWrapper.actionStream.listen((action) {
      _actionController.add(action);
    });
  }

  @override
  Stream<String> get actionStream => _actionController.stream;

  @override
  Future<Either<Failure, bool>> startService({
    String? title,
    String? content,
  }) async {
    try {
      final success = await _platformWrapper.startForegroundService(
        title: title,
        content: content,
      );
      return Right(success);
    } catch (e) {
      return Left(ServerFailure('Failed to start background service: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> stopService() async {
    try {
      final success = await _platformWrapper.stopForegroundService();
      return Right(success);
    } catch (e) {
      return Left(ServerFailure('Failed to stop background service: $e'));
    }
  }

  @override
  Future<bool> isRunning() async {
    try {
      return await _platformWrapper.isServiceRunning();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Either<Failure, bool>> updateNotification({
    required String title,
    required String content,
  }) async {
    try {
      final success = await _platformWrapper.updateNotification(
        title: title,
        content: content,
      );
      return Right(success);
    } catch (e) {
      return Left(ServerFailure('Failed to update notification: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> acquireWakeLock({Duration? timeout}) async {
    try {
      int timeoutMs = timeout?.inMilliseconds ?? defaultWakeLockTimeoutMs;
      // Clamp strictly to safe bounds to protect battery
      if (timeoutMs < minWakeLockTimeoutMs) {
        timeoutMs = minWakeLockTimeoutMs;
      } else if (timeoutMs > maxWakeLockTimeoutMs) {
        timeoutMs = maxWakeLockTimeoutMs;
      }

      final success =
          await _platformWrapper.acquireWakeLock(timeoutMs: timeoutMs);
      return Right(success);
    } catch (e) {
      return Left(ServerFailure('Failed to acquire wake lock: $e'));
    }
  }

  @override
  Future<Either<Failure, bool>> releaseWakeLock() async {
    try {
      final success = await _platformWrapper.releaseWakeLock();
      return Right(success);
    } catch (e) {
      return Left(ServerFailure('Failed to release wake lock: $e'));
    }
  }

  @override
  Future<bool> isWakeLockHeld() async {
    try {
      return await _platformWrapper.isWakeLockHeld();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QuickTileState> getTileState() async {
    try {
      final stateStr = await _platformWrapper.getQuickTileState();
      switch (stateStr.toLowerCase().trim()) {
        case 'active':
          return QuickTileState.active;
        case 'inactive':
          return QuickTileState.inactive;
        case 'unavailable':
        default:
          return QuickTileState.unavailable;
      }
    } catch (_) {
      return QuickTileState.unavailable;
    }
  }

  @override
  Future<Either<Failure, bool>> setTileState(QuickTileState state) async {
    try {
      if (state == QuickTileState.unavailable) {
        return const Right(false);
      }
      final isActive = state == QuickTileState.active;
      final success = await _platformWrapper.setQuickTileState(isActive);
      return Right(success);
    } catch (e) {
      return Left(ServerFailure('Failed to set quick tile state: $e'));
    }
  }

  @override
  Future<Either<Failure, QuickTileState>> toggleTileState() async {
    try {
      final currentState = await getTileState();
      if (currentState == QuickTileState.unavailable) {
        return const Left(
          ServerFailure('Quick Settings Tile unavailable on this device'),
        );
      }

      final targetState = currentState == QuickTileState.active
          ? QuickTileState.inactive
          : QuickTileState.active;

      final setRes = await setTileState(targetState);
      final Either<Failure, QuickTileState> result =
          setRes.fold<Either<Failure, QuickTileState>>(
        (failure) => Left(failure),
        (_) => Right(targetState),
      );
      return result;
    } catch (e) {
      return Left(ServerFailure('Failed to toggle quick tile state: $e'));
    }
  }

  @override
  Future<String?> getPendingAction() async {
    try {
      return await _platformWrapper.getPendingAction();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearPendingAction() async {
    try {
      await _platformWrapper.clearPendingAction();
    } catch (_) {}
  }

  @override
  void dispose() {
    _actionSubscription?.cancel();
    _actionController.close();
  }
}
