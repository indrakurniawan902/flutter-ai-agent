// T24.2 evidence harness: the bounded tool executors, over a REAL bridge.
//
// Wires the production stack (GatewayClient -> GatewayDeviceRpcReceiver ->
// ToolRegistry -> HealthService / DocBuilderSkill) against a live device
// bridge, so an inbound `tool_call_request` for `get_health_data` /
// `export_document_pdf` runs the real code path and the response travels back
// over the socket.
//
// The health wrapper deliberately reproduces the Android-14 device condition
// the card was filed for: `readRecords` returns a Future that NEVER settles
// when the requested range actually contains records. Pre-fix, that hung the
// tool until the bridge's 30s device budget expired and then dropped the
// socket (close 4001). With the fix, the call must settle well under 30s as a
// structured failure -- never `device_timeout`.
//
// Skipped automatically unless FLAMES_T242_URL and FLAMES_T242_TOKEN are set,
// so CI and the normal suite are unaffected.
//
// Run against the local test bridge:
//   FLAMES_T242_URL=ws://127.0.0.1:8898/device/ws \
//   FLAMES_T242_TOKEN=<issued for flutter_client> \
//   FLAMES_T242_SECONDS=120 \
//   flutter test test/integration/t242_tool_timeout_bridge_test.dart
@Tags(['manual', 'integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_client.dart';
import 'package:flutter_ai_agent/data/datasources/skills/doc_builder_skill.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/health_service.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';
import 'package:flutter_ai_agent/domain/tools/chat/file_workspace_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/health_metrics.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';

/// Reproduces the device condition: availability and permissions answer, but
/// the metric read never replies (Android 14 `readRecords` with records in
/// range). This is the exact pathological path the card was filed for.
class _SilentReadHealthPlatform implements HealthPlatformWrapper {
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
  }) =>
      // Never settles: the silent platform call.
      Completer<Map<String, dynamic>?>().future;
}

/// Writes into a real temp directory instead of the platform documents dir,
/// which does not exist under `flutter test`. The render + write path under
/// test is the production one; only the base directory is swapped.
class _TempFileSystem implements FileSystemWrapper {
  _TempFileSystem(this.root);

  final String root;
  final List<String> written = <String>[];

  @override
  Future<String> getDocumentsDirectory() async => root;

  @override
  Future<void> writeFileAsBytes(String path, Uint8List bytes) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(bytes);
    written.add('$path (${bytes.length} bytes)');
  }

  @override
  Future<bool> fileExists(String path) => File(path).exists();

  @override
  Future<bool> directoryExists(String path) => Directory(path).exists();

  @override
  Future<bool> isDirectory(String path) async =>
      await FileSystemEntity.type(path) == FileSystemEntityType.directory;

  @override
  Future<Uint8List> readFileAsBytes(String path) => File(path).readAsBytes();

  @override
  Future<String> readFileAsString(String path) => File(path).readAsString();

  @override
  Future<List<FileSystemEntity>> listDirectory(String path,
          {bool recursive = false}) =>
      Directory(path).list(recursive: recursive).toList();

  @override
  Future<FileStat> stat(String path) => FileStat.stat(path);

  @override
  Future<int> fileLength(String path) => File(path).length();

  @override
  Future<bool> checkPermission() async => true;

  @override
  Future<bool> requestPermission() async => true;
}

void main() {
  final url = Platform.environment['FLAMES_T242_URL'];
  final token = Platform.environment['FLAMES_T242_TOKEN'];
  final seconds =
      int.tryParse(Platform.environment['FLAMES_T242_SECONDS'] ?? '') ?? 120;
  final readyFile = Platform.environment['FLAMES_T242_READY_FILE'] ??
      '/tmp/t242_harness_ready';
  final logFile =
      Platform.environment['FLAMES_T242_LOG'] ?? '/tmp/t242_harness.log';
  final enabled = url != null && token != null && token.isNotEmpty;
  final wsUrl = url ?? '';
  final deviceToken = token ?? '';

  test(
    'bounded tool executors answer over a real bridge',
    skip: enabled
        ? false
        : 'set FLAMES_T242_URL and FLAMES_T242_TOKEN to run this harness',
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

      final docRoot = Directory.systemTemp.createTempSync('t242_docs_').path;
      final fileSystem = _TempFileSystem(docRoot);

      final registry = ToolRegistry(
        healthService: HealthService(platform: _SilentReadHealthPlatform()),
      );
      DocBuilderSkill.registerTools(registry, fileSystem: fileSystem);

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
            't242 tool_call tool=${message.tool} args=${jsonEncode(message.arguments)}',
          );
        }
      });

      addTearDown(() async {
        await messageSub.cancel();
        receiver.dispose();
        await client.dispose();
        if (ready.existsSync()) ready.deleteSync();
      });

      logLine('t242 connecting url=$wsUrl docRoot=$docRoot');
      await client.connect(wsUrl, token: deviceToken);

      final authDeadline = DateTime.now().add(const Duration(seconds: 15));
      while (client.state != GatewayConnectionState.connected &&
          DateTime.now().isBefore(authDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(client.state, GatewayConnectionState.connected,
          reason: 'never authenticated against the bridge');
      logLine('t242 connected state=${client.state.name}');

      receiver.startListening();
      ready.writeAsStringSync('ready');
      logLine('t242 ready_file=$readyFile');

      final sw = Stopwatch()..start();
      while (sw.elapsed.inSeconds < seconds) {
        if (client.state != GatewayConnectionState.connected) {
          fail('socket dropped after ${sw.elapsed.inSeconds}s; '
              'state=${client.state.name}');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }

      logLine(
        't242 final counts=${jsonEncode({'toolCalls': toolCalls, 'writes': fileSystem.written})}',
      );
    },
    timeout: Timeout(Duration(seconds: seconds + 90)),
  );
}
