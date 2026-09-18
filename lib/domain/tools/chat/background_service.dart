import 'package:dartz/dartz.dart';

import 'package:flutter_ai_agent/common/failure.dart';

enum QuickTileState { active, inactive, unavailable }

/// Outcome of a tile toggle: the state the device actually settled on, whether it
/// differs from the state observed before the write, and why.
class TileStateChange {
  const TileStateChange({
    required this.state,
    required this.changed,
    required this.reason,
  });

  final QuickTileState state;
  final bool changed;
  final String reason;
}

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
  Future<Either<Failure, TileStateChange>> toggleTileState();
  Stream<String> get actionStream;
  Future<String?> getPendingAction();
  Future<void> clearPendingAction();
  void dispose();
}
