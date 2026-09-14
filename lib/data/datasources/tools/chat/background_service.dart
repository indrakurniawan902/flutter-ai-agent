import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart';
import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/failure_message.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';

abstract class BackgroundServicePlatformWrapper {
  Future<dynamic> invokeMethod(String method, [Map<String, dynamic>? arguments]);
  void setActionHandler(void Function(String action)? onAction);
}

class DefaultBackgroundServicePlatformWrapper
    implements BackgroundServicePlatformWrapper {
  DefaultBackgroundServicePlatformWrapper({MethodChannel? channel})
      : _channel = channel ??
            const MethodChannel('ai.hermes.flames/background_service');

  final MethodChannel _channel;

  @override
  Future<dynamic> invokeMethod(
    String method, [
    Map<String, dynamic>? arguments,
  ]) =>
      _channel.invokeMethod<dynamic>(method, arguments);

  @override
  void setActionHandler(void Function(String action)? onAction) {
    try {
      if (onAction == null) {
        _channel.setMethodCallHandler(null);
        return;
      }
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onActionReceived' && call.arguments is String) {
          onAction(call.arguments as String);
        }
      });
    } catch (_) {
      // ServicesBinding not initialized (pure Dart tests / DI startup).
    }
  }
}

@LazySingleton(as: BackgroundServiceBase)
class BackgroundService implements BackgroundServiceBase {
  BackgroundService({BackgroundServicePlatformWrapper? channel})
      : _channel = channel ?? DefaultBackgroundServicePlatformWrapper() {
    _channel.setActionHandler(_onAction);
  }

  @factoryMethod
  factory BackgroundService.create() => BackgroundService();

  static const defaultWakeLockTimeout = Duration(seconds: 30);
  static const minWakeLockTimeout = Duration(seconds: 1);
  static const maxWakeLockTimeout = Duration(seconds: 60);

  final BackgroundServicePlatformWrapper _channel;
  final _actionController = StreamController<String>.broadcast();

  static Duration clampWakeLockTimeout(Duration? timeout) {
    final value = timeout ?? defaultWakeLockTimeout;
    if (value < minWakeLockTimeout) return minWakeLockTimeout;
    if (value > maxWakeLockTimeout) return maxWakeLockTimeout;
    return value;
  }

  @override
  Stream<String> get actionStream => _actionController.stream;

  @override
  Future<Either<Failure, bool>> startService({
    String? title,
    String? content,
  }) async {
    try {
      final result = await _channel.invokeMethod('startForegroundService', {
        'title': title ?? 'Flames Agent Active',
        'content': content ?? 'Listening in background',
      });
      return Right(result == true);
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Start service failed'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, bool>> stopService() async {
    try {
      final result = await _channel.invokeMethod('stopForegroundService');
      return Right(result == true);
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Stop service failed'),
        ),
      );
    }
  }

  @override
  Future<bool> isRunning() async {
    try {
      final result = await _channel.invokeMethod('isServiceRunning');
      return result == true;
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
      final result = await _channel.invokeMethod('updateNotification', {
        'title': title,
        'content': content,
      });
      return Right(result == true);
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Update notification failed'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, bool>> acquireWakeLock({Duration? timeout}) async {
    try {
      final bounded = clampWakeLockTimeout(timeout);
      final result = await _channel.invokeMethod('acquireWakeLock', {
        'timeoutMs': bounded.inMilliseconds,
      });
      return Right(result == true);
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Acquire wake lock failed'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, bool>> releaseWakeLock() async {
    try {
      final result = await _channel.invokeMethod('releaseWakeLock');
      return Right(result == true);
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Release wake lock failed'),
        ),
      );
    }
  }

  @override
  Future<bool> isWakeLockHeld() async {
    try {
      final result = await _channel.invokeMethod('isWakeLockHeld');
      return result == true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<QuickTileState> getTileState() async {
    try {
      final result = await _channel.invokeMethod('getQuickTileState');
      return switch (result?.toString()) {
        'active' => QuickTileState.active,
        'inactive' => QuickTileState.inactive,
        _ => QuickTileState.unavailable,
      };
    } catch (_) {
      return QuickTileState.unavailable;
    }
  }

  @override
  Future<Either<Failure, bool>> setTileState(QuickTileState state) async {
    try {
      final result = await _channel.invokeMethod('setQuickTileState', {
        'active': state == QuickTileState.active,
      });
      return Right(result == true);
    } catch (e) {
      return Left(
        ServerFailure(
          FailureMessage.humanize(e, context: 'Set tile state failed'),
        ),
      );
    }
  }

  @override
  Future<Either<Failure, QuickTileState>> toggleTileState() async {
    final current = await getTileState();
    final next = current == QuickTileState.active
        ? QuickTileState.inactive
        : QuickTileState.active;
    final result = await setTileState(next);
    return result.fold(
      (failure) => Left(failure),
      (_) => Right(next),
    );
  }

  @override
  Future<String?> getPendingAction() async {
    try {
      final result = await _channel.invokeMethod('getPendingAction');
      if (result == null) return null;
      final action = result.toString();
      return action.isEmpty ? null : action;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> clearPendingAction() async {
    try {
      await _channel.invokeMethod('clearPendingAction');
    } catch (_) {}
  }

  @override
  void dispose() {
    _channel.setActionHandler(null);
    _actionController.close();
  }

  void _onAction(String action) {
    if (!_actionController.isClosed) _actionController.add(action);
  }
}
