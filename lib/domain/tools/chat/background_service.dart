import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

enum QuickTileState { active, inactive, unavailable }

abstract class BackgroundServiceBase {
  Future<Either<Failure, bool>> startService({String? title, String? content});
  Future<Either<Failure, bool>> stopService();
  Future<bool> isRunning();
  Future<Either<Failure, bool>> updateNotification({
    required String title,
    required String content,
  });
  Future<Either<Failure, bool>> acquireWakeLock({Duration? timeout});
  Future<Either<Failure, bool>> releaseWakeLock();
  Future<bool> isWakeLockHeld();
  Future<QuickTileState> getTileState();
  Future<Either<Failure, bool>> setTileState(QuickTileState state);
  Future<Either<Failure, QuickTileState>> toggleTileState();
  Stream<String> get actionStream;
  Future<String?> getPendingAction();
  Future<void> clearPendingAction();
  void dispose();
}
