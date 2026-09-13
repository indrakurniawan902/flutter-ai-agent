import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';
import 'package:flutter_ai_agent/domain/repositories/action_center/action_center_repository.dart';
import 'package:injectable/injectable.dart';

/// Abstraction over a battery-level reader (platform channel lives in the
/// data layer). Kept minimal so the watcher is pure and testable.
abstract class AmbientBatteryReader {
  Future<int> readBatteryLevel();
}

/// Zero-Token Heuristic Guard.
///
/// Decides whether an ambient signal changed enough (and recently enough)
/// to justify waking the model/LLM synthesis boundary. Returns false unless
/// both the magnitude and the cooldown gates pass.
@injectable
class ZeroTokenGate {
  const ZeroTokenGate();

  /// Percentage-point delta required to consider a change material.
  bool shouldWake({
    required int previousValue,
    required int currentValue,
    required int minDeltaPct,
    required DateTime? lastWakeAt,
    required Duration cooldown,
    required DateTime now,
  }) {
    final delta = (currentValue - previousValue).abs();
    if (delta < minDeltaPct) return false;
    if (lastWakeAt != null && now.difference(lastWakeAt) < cooldown) {
      return false;
    }
    return true;
  }
}

/// Watches ambient battery level and only posts an Action Center item when a
/// material change passes the [ZeroTokenGate]. The [synthesize] callback is
/// the sole model/LLM boundary: it is invoked only when the gate opens, so
/// trivial fluctuations cost zero tokens.
class ProactiveWatcher {
  final AmbientBatteryReader _reader;
  final ZeroTokenGate _gate;
  final ActionCenterRepository _repo;
  final int minDeltaPct;
  final Duration cooldown;
  final Future<ActionItem> Function(int level) synthesize;

  /// Last battery level we evaluated. Seeded in tests via constructor.
  int? _lastKnownLevel;

  /// When we last woke the synthesis boundary.
  DateTime? _lastWakeAt;

  ProactiveWatcher({
    required AmbientBatteryReader reader,
    required ZeroTokenGate gate,
    required ActionCenterRepository repo,
    required this.synthesize,
    this.minDeltaPct = 5,
    this.cooldown = const Duration(minutes: 30),
    int? lastKnownLevel,
    DateTime? lastWakeAt,
  })  : _reader = reader,
        _gate = gate,
        _repo = repo,
        _lastKnownLevel = lastKnownLevel,
        _lastWakeAt = lastWakeAt;

  /// Exposes the in-memory last-known level for tests/telemetry.
  int? get lastKnownLevel => _lastKnownLevel;

  /// Exposes the in-memory last-wake time for tests/telemetry.
  DateTime? get lastWakeAt => _lastWakeAt;

  /// Reads the current level and, only if [ZeroTokenGate.shouldWake] passes,
  /// synthesizes an item and posts it. Returns whether it woke.
  Future<bool> evaluateBattery({DateTime? now}) async {
    final current = await _reader.readBatteryLevel();
    final effectiveNow = now ?? DateTime.now();
    final previous = _lastKnownLevel ?? current;

    final woke = _gate.shouldWake(
      previousValue: previous,
      currentValue: current,
      minDeltaPct: minDeltaPct,
      lastWakeAt: _lastWakeAt,
      cooldown: cooldown,
      now: effectiveNow,
    );

    _lastKnownLevel = current;
    if (!woke) return false;

    final item = await synthesize(current);
    await _repo.addItem(item);
    _lastWakeAt = effectiveNow;
    return true;
  }
}
