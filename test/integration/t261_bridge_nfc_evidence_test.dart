// T26.1 bridge evidence harness: the FIXED NFC tool path over a REAL bridge.
//
// Hosts a `flutter_client` device on the live Hermes bridge with the
// production NFC tools published (real `NfcService`, fake platform seam). The
// driver `tool/t261_bridge_evidence.py` calls `nfc_read_tag` and
// `nfc_read_emoney_balance`; with no card ever tapped, both must answer with
// the DEVICE's own 20s window (`NFC scan timed out`), never the old registry
// bound (`tool_timeout: ... within 10s`).
//
// Skipped automatically unless FLAMES_T261_URL and FLAMES_T261_TOKEN are set.
//
// Run against the local test bridge:
//   FLAMES_T261_URL=ws://127.0.0.1:8898/device/ws \
//   FLAMES_T261_TOKEN=<issued for flutter_client> \
//   FLAMES_T261_SECONDS=120 \
//   flutter test test/integration/t261_bridge_nfc_evidence_test.dart --tags manual
@Tags(['manual', 'integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_client.dart';
import 'package:flutter_ai_agent/data/datasources/tools/device/nfc_service.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces `DefaultNfcPlatformWrapper`'s contract without a plugin: the
/// platform is enabled, but no card is ever tapped, so every read waits the
/// supplied `timeout` and throws `TimeoutException('NFC scan timed out')`.
class _NoCardNfcPlatform implements NfcPlatformWrapper {
  final List<Duration> recordedTimeouts = <Duration>[];

  @override
  Future<String> availability() async => 'enabled';

  @override
  Future<T> runWithCard<T>({
    required Set<String> pollingOptions,
    Duration timeout = kNfcScanTimeout,
    required Future<T> Function(RawNfcCard card) action,
  }) async {
    recordedTimeouts.add(timeout);
    await Future<void>.delayed(timeout);
    throw TimeoutException('NFC scan timed out', timeout);
  }

  @override
  Future<NfcScanResult> scan({
    required Set<String> pollingOptions,
    Duration timeout = kNfcScanTimeout,
  }) =>
      runWithCard<NfcScanResult>(
        pollingOptions: pollingOptions,
        timeout: timeout,
        action: (card) async => NfcScanResult(card: card),
      );

  @override
  Future<void> cancel() async {}
}

void main() {
  final url = Platform.environment['FLAMES_T261_URL'];
  final token = Platform.environment['FLAMES_T261_TOKEN'];
  final seconds =
      int.tryParse(Platform.environment['FLAMES_T261_SECONDS'] ?? '') ?? 120;
  final readyFile = Platform.environment['FLAMES_T261_READY_FILE'] ??
      '/tmp/t261_harness_ready';
  final logFile =
      Platform.environment['FLAMES_T261_LOG'] ?? '/tmp/t261_harness.log';
  final enabled = url != null && token != null && token.isNotEmpty;
  final wsUrl = url ?? '';
  final deviceToken = token ?? '';

  test(
    'the fixed NFC tools answer over a real bridge',
    skip: enabled
        ? false
        : 'set FLAMES_T261_URL and FLAMES_T261_TOKEN to run this harness',
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

      final nfcPlatform = _NoCardNfcPlatform();
      final registry = ToolRegistry(
        nfcService: NfcService(platformWrapper: nfcPlatform),
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
            't261 tool_call tool=${message.tool} '
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

      logLine('t261 connecting url=$wsUrl');
      await client.connect(wsUrl, token: deviceToken);

      final authDeadline = DateTime.now().add(const Duration(seconds: 15));
      while (client.state != GatewayConnectionState.connected &&
          DateTime.now().isBefore(authDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(client.state, GatewayConnectionState.connected,
          reason: 'never authenticated against the bridge');
      logLine('t261 connected state=${client.state.name}');

      receiver.startListening();
      ready.writeAsStringSync('ready');
      logLine('t261 ready_file=$readyFile');

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
        't261 final counts=${jsonEncode({
          'toolCalls': toolCalls,
          'wrapperTimeouts': nfcPlatform.recordedTimeouts
              .map((timeout) => timeout.inSeconds)
              .toList(),
        })}',
      );
    },
    timeout: Timeout(Duration(seconds: seconds + 90)),
  );
}
