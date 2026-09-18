import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/presentation/screen/gateway/cubit/gateway_link_cubit.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../../helpers/mocks.dart';

/// Recording [BackgroundServiceBase] fake that mirrors the running / wake-lock
/// state so the cubit's `isRunning()` / `isWakeLockHeld()` pre-checks behave
/// like the real Kotlin service.
class _FakeBackgroundService implements BackgroundServiceBase {
  int startServiceCalls = 0;
  int stopServiceCalls = 0;
  int acquireWakeLockCalls = 0;
  int releaseWakeLockCalls = 0;
  Duration? lastWakeLockTimeout;

  bool _running = false;
  bool _held = false;

  @override
  Future<Either<Failure, bool>> startService({String? title, String? content}) async {
    startServiceCalls++;
    _running = true;
    return const Right(true);
  }

  @override
  Future<Either<Failure, bool>> stopService() async {
    stopServiceCalls++;
    _running = false;
    return const Right(true);
  }

  @override
  Future<bool> isRunning() async => _running;

  @override
  Future<Either<Failure, bool>> updateNotification({
    required String title,
    required String content,
  }) async =>
      const Right(true);

  @override
  Future<Either<Failure, bool>> acquireWakeLock({Duration? timeout}) async {
    acquireWakeLockCalls++;
    lastWakeLockTimeout = timeout;
    _held = true;
    return const Right(true);
  }

  @override
  Future<Either<Failure, bool>> releaseWakeLock() async {
    releaseWakeLockCalls++;
    _held = false;
    return const Right(true);
  }

  @override
  Future<bool> isWakeLockHeld() async => _held;

  @override
  Future<QuickTileState> getTileState() async => QuickTileState.inactive;

  @override
  Future<Either<Failure, bool>> setTileState(QuickTileState state) async =>
      const Right(true);

  @override
  Future<Either<Failure, TileStateChange>> toggleTileState() async =>
      const Right(TileStateChange(
        state: QuickTileState.inactive,
        changed: true,
        reason: 'toggled',
      ));

  @override
  Stream<String> get actionStream => const Stream<String>.empty();

  @override
  Future<String?> getPendingAction() async => null;

  @override
  Future<void> clearPendingAction() async {}

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockGatewayClient client;
  late _FakeBackgroundService bg;
  late StreamController<GatewayConnectionState> stateCtrl;
  late ServerProfile profile;
  late GatewayLinkCubit cubit;
  late GatewayConnectionState current;
  late int connectCount;

  setUpAll(() {
    registerFallbackValue(const ServerProfile(
      id: 'fb',
      name: 'fb',
      gatewayUrl: 'ws://fb/rpc',
      token: 'fb',
    ));
  });

  setUp(() {
    client = MockGatewayClient();
    bg = _FakeBackgroundService();
    stateCtrl = StreamController<GatewayConnectionState>.broadcast();
    profile = const ServerProfile(
      id: 'p1',
      name: 'node',
      gatewayUrl: 'ws://hermes:8642/rpc',
      token: 'secret',
    );
    current = GatewayConnectionState.disconnected;
    connectCount = 0;

    when(() => client.state).thenAnswer((_) => current);
    when(() => client.stateStream).thenAnswer((_) => stateCtrl.stream);
    when(() => client.connectWithProfile(any())).thenAnswer((_) async {
      connectCount++;
    });
  });

  Future<void> pump() => pumpEventQueue();

  void emit(GatewayConnectionState s) {
    current = s;
    stateCtrl.add(s);
  }

  tearDown(() async {
    await cubit.close();
    await stateCtrl.close();
  });

  group('GatewayLinkCubit - service policy', () {
    test('1. connected + not running -> startService once + acquireWakeLock',
        () async {
      cubit = GatewayLinkCubit(
        gatewayClient: client,
        backgroundService: bg,
      );
      await pump();

      emit(GatewayConnectionState.connected);
      await pump();

      expect(bg.startServiceCalls, 1);
      expect(bg.acquireWakeLockCalls, 1);
      expect(bg.lastWakeLockTimeout, Duration(minutes: 10));
      expect(cubit.state.serviceRunning, isTrue);
      expect(cubit.state.wakeLockHeld, isTrue);
      expect(cubit.state.lastConnectionState, GatewayConnectionState.connected);
    });

    test('2. disconnected -> releaseWakeLock + stopService', () async {
      cubit = GatewayLinkCubit(
        gatewayClient: client,
        backgroundService: bg,
      );
      await pump();

      emit(GatewayConnectionState.connected);
      await pump();
      emit(GatewayConnectionState.disconnected);
      await pump();

      expect(bg.releaseWakeLockCalls, 1);
      expect(bg.stopServiceCalls, 1);
      expect(cubit.state.wakeLockHeld, isFalse);
      expect(cubit.state.serviceRunning, isFalse);
    });

    test('3. connected -> connecting -> connected does not double-start',
        () async {
      cubit = GatewayLinkCubit(
        gatewayClient: client,
        backgroundService: bg,
      );
      await pump();

      emit(GatewayConnectionState.connected);
      await pump();
      emit(GatewayConnectionState.connecting);
      await pump();
      emit(GatewayConnectionState.connected);
      await pump();

      expect(bg.startServiceCalls, 1);
      expect(bg.acquireWakeLockCalls, 1);
    });
  });

  group('GatewayLinkCubit - lifecycle', () {
    test('4. resumed while disconnected + stored profile -> one re-fire',
        () async {
      cubit = GatewayLinkCubit(
        gatewayClient: client,
        backgroundService: bg,
      );
      await pump();

      await cubit.startWithProfile(profile);
      await pump();
      verify(() => client.connectWithProfile(profile)).called(1);

      clearInteractions(client);
      current = GatewayConnectionState.disconnected;
      connectCount = 0;

      cubit.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pump();

      expect(connectCount, 1);
      verify(() => client.connectWithProfile(profile)).called(1);
    });

    test('5. 12 flap cycles never stop retries (no permanent give-up)',
        () async {
      cubit = GatewayLinkCubit(
        gatewayClient: client,
        backgroundService: bg,
      );
      await pump();
      await cubit.startWithProfile(profile);
      await pump();

      for (var i = 0; i < 12; i++) {
        emit(GatewayConnectionState.connected);
        await pump();
        emit(GatewayConnectionState.disconnected);
        await pump();
      }

      expect(cubit.state.linkFlaps, 12);

      clearInteractions(client);
      current = GatewayConnectionState.disconnected;
      connectCount = 0;
      cubit.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await pump();

      expect(connectCount, 1);
      verify(() => client.connectWithProfile(any())).called(1);
    });
  });

  group('GatewayLinkCubit - teardown', () {
    test('6. close() cancels subscription; emitting after close is inert',
        () async {
      cubit = GatewayLinkCubit(
        gatewayClient: client,
        backgroundService: bg,
      );
      await pump();
      emit(GatewayConnectionState.connected);
      await pump();

      expect(bg.startServiceCalls, 1);
      final stateBeforeClose = cubit.state;

      await cubit.close();
      final startsBeforeEmit = bg.startServiceCalls;

      expect(() => stateCtrl.add(GatewayConnectionState.connected),
          returnsNormally);
      await pump();

      expect(bg.startServiceCalls, startsBeforeEmit);
      expect(cubit.state, stateBeforeClose);
    });
  });
}
