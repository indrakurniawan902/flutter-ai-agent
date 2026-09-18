// T26.2 evidence harness: the health-read error contract, over a REAL bridge.
//
// Wires the production stack (GatewayClient -> GatewayDeviceRpcReceiver ->
// real ToolRegistry -> HealthService) against a live device bridge, exactly
// like the T24.2 harness, so an inbound `tool_call_request` for
// `get_health_data` runs the real code path and the response travels back over
// the socket.
//
// The fake HealthPlatformWrapper reproduces the Android-14 device condition
// (the client-side IReadRecordsResponseCallback dies unmarshalling the reply,
// so the coroutine never resumes) as the *structured* error the Kotlin fix now
// returns instead of hanging: no `null`, no silent timeout.
//
// ENCODING (one bridge run, three cases; also printed by the python driver):
//   endDate year 2001 -> platform-error map     (health_platform_error)
//   endDate year 2002 -> partial-success payload (summary.total=1234,
//                        records_unavailable=true)
//   anything else     -> plain empty success payload
//
// Skipped automatically unless FLAMES_T262_URL and FLAMES_T262_TOKEN are set,
// so CI and the normal suite are unaffected and never open a socket.
//
// Run against the local test bridge (from the repo root):
//   FLAMES_T262_URL=ws://127.0.0.1:8898/device/ws \
//   FLAMES_T262_TOKEN=<issued for flutter_client> \
//   FLAMES_T262_SECONDS=120 \
//   flutter test test/integration/t262_health_read_bridge_test.dart
@Tags(['manual', 'integration'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_client.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/health_service.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';
import 'package:flutter_ai_agent/domain/tools/chat/health_metrics.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scripted platform wrapper. Behaviour is keyed off the requested range so a
/// single bridge run can drive all three cases:
///   endDate year 2001 -> the real platform error the device produces;
///   endDate year 2002 -> aggregate succeeded, record read failed;
///   otherwise         -> a plain empty success.
class _ScriptedHealthPlatform implements HealthPlatformWrapper {
  static const String platformErrorMessage =
      'IllegalArgumentException: bad record';

  @override
  Future<Map<String, dynamic>?> availability() async =>
      <String, dynamic>{'status': 'available', 'sdk_int': 34};

  @override
  Future<List<String>> grantedPermissions() async => <String>[
        for (final metric in HealthMetrics.supported)
          if (HealthMetrics.permissionByMetric[metric] != null)
            HealthMetrics.permissionByMetric[metric]!,
      ];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<Map<String, dynamic>?> readMetric({
    required String metric,
    required int startTimeMs,
    required int endTimeMs,
  }) async {
    final start =
        DateTime.fromMillisecondsSinceEpoch(startTimeMs, isUtc: true)
            .toIso8601String();
    final end = DateTime.fromMillisecondsSinceEpoch(endTimeMs, isUtc: true)
        .toIso8601String();
    final year =
        DateTime.fromMillisecondsSinceEpoch(endTimeMs, isUtc: true).year;
    if (year == 2001) {
      return <String, dynamic>{
        'metric': metric,
        'start': start,
        'end': end,
        'error_code': 'health_platform_error',
        'error_message': platformErrorMessage,
      };
    }
    if (year == 2002) {
      return <String, dynamic>{
        'metric': metric,
        'start': start,
        'end': end,
        'records': <dynamic>[],
        'summary': <String, dynamic>{'total': 1234},
        'records_unavailable': true,
        'records_error': platformErrorMessage,
      };
    }
    return <String, dynamic>{
      'metric': metric,
      'start': start,
      'end': end,
      'records': <dynamic>[],
      'summary': <String, dynamic>{'total': 0},
    };
  }
}

void main() {
  final url = Platform.environment['FLAMES_T262_URL'];
  final token = Platform.environment['FLAMES_T262_TOKEN'];
  final seconds =
      int.tryParse(Platform.environment['FLAMES_T262_SECONDS'] ?? '') ?? 120;
  final readyFile = Platform.environment['FLAMES_T262_READY_FILE'] ??
      'build/t262_harness_ready';
  final logFile =
      Platform.environment['FLAMES_T262_LOG'] ?? 'build/t262_harness.log';
  // A distinct client id by default: the bridge keys sessions by device_id
  // (`self._devices[device_id] = session`), so reusing the phone's
  // 'flutter_client' would evict the live device's session for the duration of
  // the run. Issue a token for whatever id is set here.
  final clientId =
      Platform.environment['FLAMES_T262_CLIENT_ID'] ?? 't262_harness';
  final enabled = url != null && token != null && token.isNotEmpty;
  final wsUrl = url ?? '';
  final deviceToken = token ?? '';

  test(
    'health read error contract answers over a real bridge',
    skip: enabled
        ? false
        : 'set FLAMES_T262_URL and FLAMES_T262_TOKEN to run this harness',
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

      final registry = ToolRegistry(
        healthService: HealthService(platform: _ScriptedHealthPlatform()),
      );

      final client = GatewayClient(
        clientId: clientId,
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
            't262 tool_call tool=${message.tool} args=${jsonEncode(message.arguments)}',
          );
        }
      });

      addTearDown(() async {
        await messageSub.cancel();
        receiver.dispose();
        await client.dispose();
        if (ready.existsSync()) ready.deleteSync();
      });

      logLine(
        't262 encoding=endDate_year_2001:platform_error,'
        'year_2002:partial_success(total=1234,records_unavailable),'
        'else:empty_success',
      );
      logLine('t262 connecting url=$wsUrl');
      await client.connect(wsUrl, token: deviceToken);

      final authDeadline = DateTime.now().add(const Duration(seconds: 15));
      while (client.state != GatewayConnectionState.connected &&
          DateTime.now().isBefore(authDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(client.state, GatewayConnectionState.connected,
          reason: 'never authenticated against the bridge');
      logLine('t262 connected state=${client.state.name}');

      receiver.startListening();
      ready.writeAsStringSync('ready');
      logLine('t262 ready_file=$readyFile');

      final sw = Stopwatch()..start();
      while (sw.elapsed.inSeconds < seconds) {
        if (client.state != GatewayConnectionState.connected) {
          fail('socket dropped after ${sw.elapsed.inSeconds}s; '
              'state=${client.state.name}');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }

      logLine('t262 final toolCalls=$toolCalls');
    },
    timeout: Timeout(Duration(seconds: seconds + 90)),
  );
}
