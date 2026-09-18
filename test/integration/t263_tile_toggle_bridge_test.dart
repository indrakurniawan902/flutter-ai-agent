// T26.3 bridge evidence harness: the tile toggle reports the state the device
// actually settled on, over a REAL bridge.
//
// Hosts the production stack (GatewayClient -> GatewayDeviceRpcReceiver ->
// ToolRegistry -> the REAL `BackgroundService`) against a live device bridge.
// The Kotlin tile state cannot run on the host JVM, so the MethodChannel is
// modelled by a test-local device fake that reproduces MainActivity's contract,
// INCLUDING the bind/unbind transition: `getQuickTileState` answers from the
// fake's own state, `setQuickTileState` mutates it and echoes the state it
// actually settled on, and opening a system settings screen unbinds the tile
// (the app is backgrounded) exactly like the card's repro.
//
// The driver `tool/t263_tile_evidence.py` runs six interleaved toggle/get pairs
// while the tile is bound (PHASE A) and six more after the tile has unbound
// (PHASE B); every toggle must alternate and every get must agree. A
// `dropNextWrite` control lets the harness prove the card's no-op through the
// production service: one dropped device write must surface as
// `tile_state_unchanged`, never as a claimed toggle.
//
// Skipped automatically unless FLAMES_T263_URL and FLAMES_T263_TOKEN are set.
//
// Run against the local test bridge:
//   FLAMES_T263_URL=ws://127.0.0.1:8898/device/ws \
//   FLAMES_T263_TOKEN=<issued for flutter_client> \
//   FLAMES_T263_SECONDS=150 \
//   flutter test test/integration/t263_tile_toggle_bridge_test.dart --tags manual
@Tags(['manual', 'integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_client.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/intent_launcher_service_impl.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';
import 'package:flutter_ai_agent/domain/tools/chat/background_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/intent_launcher_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Test-local model of the DEVICE behind the QuickTile MethodChannel.
///
/// `setQuickTileState` mutates the fake's state and RETURNS THE ECHOED STRING
/// (what MainActivity now does), and reports whether the tile was bound at
/// write time. `dropNextWrite` makes one write echo the UNCHANGED state without
/// mutating it, reproducing the card's no-op at the device boundary.
class _TileDevicePlatform implements BackgroundServicePlatformWrapper {
  String state = 'inactive';
  bool bound = false;
  bool dropNextWrite = false;
  bool lastWriteWasBound = false;
  final List<String> transitions = <String>[];

  @override
  Future<dynamic> invokeMethod(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    switch (method) {
      case 'getQuickTileState':
        return state;
      case 'setQuickTileState':
        lastWriteWasBound = bound;
        if (dropNextWrite) {
          dropNextWrite = false;
          return state;
        }
        state = arguments?['active'] == true ? 'active' : 'inactive';
        return state;
      default:
        return null;
    }
  }

  @override
  void setActionHandler(void Function(String action)? onAction) {}

  void bindTile() {
    bound = true;
    transitions.add('bind');
  }

  void unbindTile() {
    bound = false;
    transitions.add('unbind');
  }
}

/// Opening a settings screen backgrounds the app on the real phone, which is
/// what unbinds the tile service in the card's repro.
class _BackgroundingSettingsPlatform implements SystemSettingsPlatformWrapper {
  _BackgroundingSettingsPlatform(this.device);

  final _TileDevicePlatform device;
  final List<String> opened = <String>[];

  @override
  Future<bool> openSystemSettings(String settingType) async {
    opened.add(settingType);
    device.unbindTile();
    return true;
  }
}

void main() {
  final url = Platform.environment['FLAMES_T263_URL'];
  final token = Platform.environment['FLAMES_T263_TOKEN'];
  final seconds =
      int.tryParse(Platform.environment['FLAMES_T263_SECONDS'] ?? '') ?? 150;
  final readyFile = Platform.environment['FLAMES_T263_READY_FILE'] ??
      '/tmp/t263_harness_ready';
  final logFile =
      Platform.environment['FLAMES_T263_LOG'] ?? '/tmp/t263_harness.log';
  final enabled = url != null && token != null && token.isNotEmpty;
  final wsUrl = url ?? '';
  final deviceToken = token ?? '';

  test(
    'the tile toggle reports the state the device actually settled on',
    skip: enabled
        ? false
        : 'set FLAMES_T263_URL and FLAMES_T263_TOKEN to run this harness',
    () async {
      final ready = File(readyFile);
      if (ready.existsSync()) ready.deleteSync();

      void logLine(String line) {
        final stamped = '${DateTime.now().toIso8601String()} $line';
        debugPrint(stamped);
        try {
          File(logFile).writeAsStringSync('$stamped\n', mode: FileMode.append);
        } catch (_) {
          // Logging is best-effort; never break the evidence run.
        }
      }

      final device = _TileDevicePlatform();
      final settings = _BackgroundingSettingsPlatform(device);
      final service = BackgroundService(channel: device);
      final registry = ToolRegistry(
        backgroundService: service,
        intentLauncherService: IntentLauncherServiceImpl(
          settingsWrapper: settings,
        ),
      );

      final client = GatewayClient(
        clientId: 'flutter_client',
        toolManifestProvider: registry.getOpenAiToolDefinitions,
      );
      final receiver = GatewayDeviceRpcReceiver(
        gatewayClient: client,
        toolRegistry: registry,
      );

      var toolCalls = 0;
      final messageSub = client.messageStream.listen((message) {
        if (message is GatewayToolCallRequestMessage) {
          toolCalls++;
          logLine(
            't263 tool_call tool=${message.tool} '
            'args=${jsonEncode(message.arguments)}',
          );
        }
      });

      addTearDown(() async {
        await messageSub.cancel();
        receiver.dispose();
        await client.dispose();
        if (ready.existsSync()) ready.deleteSync();
      });

      // The device-boundary no-op: one write is dropped, so the production
      // service must report `tile_state_unchanged` instead of claiming a
      // toggle. This is the card's failure mode pinned in the harness.
      device.bindTile();
      device.dropNextWrite = true;
      final noOpResult = await service.toggleTileState();
      noOpResult.fold(
        (failure) =>
            fail('drop-next-write toggle returned Left: ${failure.message}'),
        (change) {
          logLine(
            't263 drop_next_write changed=${change.changed} '
            'reason=${change.reason} state=${change.state.name} '
            'writeWasBound=${device.lastWriteWasBound}',
          );
          expect(change.changed, isFalse,
              reason: 'a dropped device write must never claim a change');
          expect(change.reason, 'state_unchanged');
          expect(change.state, isNot(QuickTileState.unavailable));
        },
      );

      logLine('t263 connecting url=$wsUrl');
      await client.connect(wsUrl, token: deviceToken);

      final authDeadline = DateTime.now().add(const Duration(seconds: 15));
      while (client.state != GatewayConnectionState.connected &&
          DateTime.now().isBefore(authDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(client.state, GatewayConnectionState.connected,
          reason: 'never authenticated against the bridge');
      logLine('t263 connected state=${client.state.name}');

      receiver.startListening();
      ready.writeAsStringSync('ready');
      logLine('t263 ready_file=$readyFile');

      final sw = Stopwatch()..start();
      while (sw.elapsed.inSeconds < seconds) {
        if (client.state != GatewayConnectionState.connected) {
          fail('socket dropped after ${sw.elapsed.inSeconds}s; '
              'state=${client.state.name}');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }

      expect(client.state, GatewayConnectionState.connected,
          reason: 'socket must stay connected for the whole evidence window');

      logLine(
        't263 final counts=${jsonEncode({
          'toolCalls': toolCalls,
          'tileState': device.state,
          'bound': device.bound,
          'transitions': device.transitions,
          'settingsOpened': settings.opened,
        })}',
      );
    },
    timeout: Timeout(Duration(seconds: seconds + 90)),
  );
}
