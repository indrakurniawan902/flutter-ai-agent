// T25.1 evidence harness: geofence -> runPrompt over a REAL bridge.
//
// Wires the production stack (GatewayClient -> GatewayDeviceRpcReceiver ->
// ToolRegistry -> AmbientTriggerService -> GeofenceActionDispatcher ->
// VoicePromptDispatcherRegistry) against a live device bridge, so an inbound
// `tool_call_request` for `register_geofence` / `trigger_ambient_check` runs
// through the real code path and the response travels back over the socket.
//
// The harness records every prompt the dispatcher hands to its transport and
// writes a READY file once the socket is authenticated, so the python driver
// (tool/t251_bridge_evidence.py) knows the device is routable.
//
// Skipped automatically unless FLAMES_T251_URL and FLAMES_T251_TOKEN are set,
// so CI and the normal suite are unaffected.
//
// Run against the local test bridge:
//   FLAMES_T251_URL=ws://127.0.0.1:8898/device/ws \
//   FLAMES_T251_TOKEN=<issued for flutter_client> \
//   FLAMES_T251_SECONDS=150 \
//   flutter test test/integration/t251_geofence_dispatch_bridge_test.dart
@Tags(['manual', 'integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:dartz/dartz.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_client.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/data/services/geofence/geofence_action_dispatcher.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';
import 'package:flutter_ai_agent/domain/services/voice/voice_prompt_dispatcher.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart'
    as ambient_base;
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Battery stub: the harness never exercises battery checks, but the
/// production service demands a wrapper.
class _FakeBattery implements ambient_base.BatteryPlatformWrapper {
  @override
  Future<int> getBatteryLevel() async => 100;

  @override
  Future<bool> isCharging() async => true;
}

/// Workmanager stub: scheduling is out of scope for the evidence run.
class _FakeWorkmanager implements ambient_base.WorkmanagerPlatformWrapper {
  @override
  Future<void> ensureInitialized() async {}

  @override
  Future<void> registerPeriodicTask({Duration? frequency}) async {}

  @override
  Future<void> cancelAmbientTasks() async {}
}

/// Test-local transport that records every dispatched prompt instead of
/// speaking it, so the harness can prove the prompt reached a transport.
class _RecordingDispatcher implements VoicePromptDispatcherBase {
  final List<String> prompts = [];

  @override
  String get transportId => 't251-harness';

  @override
  bool get isReady => true;

  @override
  bool get speaksReply => false;

  @override
  Future<Either<Failure, String>> dispatch(String prompt) async {
    prompts.add(prompt);
    return Right(prompt);
  }

  @override
  Future<void> cancel() async {}
}

void main() {
  final url = Platform.environment['FLAMES_T251_URL'];
  final token = Platform.environment['FLAMES_T251_TOKEN'];
  final seconds =
      int.tryParse(Platform.environment['FLAMES_T251_SECONDS'] ?? '') ?? 150;
  final readyFile = Platform.environment['FLAMES_T251_READY_FILE'] ??
      '/tmp/t251_harness_ready';
  final logFile =
      Platform.environment['FLAMES_T251_LOG'] ?? '/tmp/t251_harness.log';
  final expectPrompt = Platform.environment['FLAMES_T251_EXPECT_PROMPT'] == '1';
  final enabled = url != null && token != null && token.isNotEmpty;
  final wsUrl = url ?? '';
  final deviceToken = token ?? '';

  test(
    'geofence runPrompt action dispatches over a real bridge',
    skip: enabled
        ? false
        : 'set FLAMES_T251_URL and FLAMES_T251_TOKEN to run this harness',
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

      final promptRegistry = VoicePromptDispatcherRegistry();
      final recorder = _RecordingDispatcher();
      promptRegistry.register(recorder);

      final ambient = AmbientTriggerService(
        battery: _FakeBattery(),
        workmanager: _FakeWorkmanager(),
        actionDispatcher: GeofenceActionDispatcher(
          promptRegistry: promptRegistry,
        ),
      );
      final toolRegistry = ToolRegistry(ambientTriggerService: ambient);

      final client = GatewayClient(
        clientId: 'flutter_client',
        toolManifestProvider: toolRegistry.getOpenAiToolDefinitions,
      );
      final receiver = GatewayDeviceRpcReceiver(
        gatewayClient: client,
        toolRegistry: toolRegistry,
      );

      var toolCalls = 0;
      final messageSub = client.messageStream.listen((message) {
        if (message is GatewayToolCallRequestMessage) {
          toolCalls++;
          logLine(
            't251 tool_call tool=${message.tool} args=${jsonEncode(message.arguments)}',
          );
        }
      });

      addTearDown(() async {
        await messageSub.cancel();
        receiver.dispose();
        await client.dispose();
        if (ready.existsSync()) ready.deleteSync();
      });

      logLine('t251 connecting url=$wsUrl');
      await client.connect(wsUrl, token: deviceToken);

      final authDeadline = DateTime.now().add(const Duration(seconds: 15));
      while (client.state != GatewayConnectionState.connected &&
          DateTime.now().isBefore(authDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(client.state, GatewayConnectionState.connected,
          reason: 'never authenticated against the bridge');
      logLine('t251 connected state=${client.state.name}');

      receiver.startListening();
      ready.writeAsStringSync('ready');
      logLine('t251 ready_file=$readyFile');

      final sw = Stopwatch()..start();
      while (sw.elapsed.inSeconds < seconds) {
        if (client.state != GatewayConnectionState.connected) {
          fail('socket dropped after ${sw.elapsed.inSeconds}s; '
              'state=${client.state.name}');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }

      logLine(
        't251 final prompts=${jsonEncode(recorder.prompts)} '
        'counts=${jsonEncode({'toolCalls': toolCalls, 'dispatches': recorder.prompts.length})}',
      );

      if (expectPrompt) {
        expect(recorder.prompts, isNotEmpty,
            reason: 'no prompt reached the transport during the harness run');
        expect(recorder.prompts.last, 'T251 evidence prompt');
      }
    },
    timeout: Timeout(Duration(seconds: seconds + 90)),
  );
}
