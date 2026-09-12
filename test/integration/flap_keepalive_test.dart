// FLAP-P0 keepalive proof (manual integration test).
//
// Connects to a REAL bridge using the app's own GatewayClient stack
// (dart:io WebSocket + protocol pingInterval + JSON heartbeat) and asserts
// the session HOLDS `connected` through `FLAMES_KEEPALIVE_IDLE` seconds of
// complete idleness. If the socket drops, the GatewayClient's gw_ws_close
// line (cause/code/reason) is printed by debugPrint before this fails.
//
// Skipped automatically unless FLAMES_KEEPALIVE_URL and FLAMES_SIM_TOKEN
// are set, so CI and the normal suite are unaffected.
//
// Run against the local test bridge:
//   FLAMES_KEEPALIVE_URL=ws://127.0.0.1:18798/device/ws \
//   FLAMES_SIM_TOKEN=<issued for flap-sim-keepalive> \
//   FLAMES_KEEPALIVE_IDLE=660 \
//   flutter test test/integration/flap_keepalive_test.dart
@Tags(['manual', 'integration'])
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_agent/data/datasources/remote/gateway/gateway_client.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final url = Platform.environment['FLAMES_KEEPALIVE_URL'];
  final token = Platform.environment['FLAMES_SIM_TOKEN'];
  final idleSeconds =
      int.tryParse(Platform.environment['FLAMES_KEEPALIVE_IDLE'] ?? '') ?? 660;
  final enabled = url != null && token != null && token.isNotEmpty;
  final wsUrl = url ?? '';
  final simToken = token ?? '';

  test(
    'gateway socket holds connected for $idleSeconds s of idle against a real bridge',
    skip: enabled ? false : 'set FLAMES_KEEPALIVE_URL and FLAMES_SIM_TOKEN to run',
    () async {

      final client = GatewayClient(
        clientId: 'flap-sim-keepalive',
        toolManifestProvider: () => [
          {
            'name': 'device_get_battery',
            'description': 'sim battery tool for the flap keepalive proof',
            'parameters': {
              'type': 'object',
              'properties': <String, dynamic>{},
            },
          },
        ],
      );
      addTearDown(client.dispose);

      final states = <String>[];
      client.stateStream.listen((s) => states.add(s.name));

      await client.connect(wsUrl, token: simToken);

      // Wait for auth_success -> connected (auth deadline is 10 s).
      final authDeadline = DateTime.now().add(const Duration(seconds: 15));
      while (client.state != GatewayConnectionState.connected &&
          DateTime.now().isBefore(authDeadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      expect(client.state, GatewayConnectionState.connected,
          reason: 'never authenticated; states seen: $states');

      final sw = Stopwatch()..start();
      while (sw.elapsed.inSeconds < idleSeconds) {
        if (client.state != GatewayConnectionState.connected) {
          fail('socket dropped after ${sw.elapsed.inSeconds}s idle; '
              'states: $states (see gw_ws_close line above for the cause)');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }

      expect(client.state, GatewayConnectionState.connected,
          reason: 'socket must still be up after ${idleSeconds}s idle; '
              'states: $states');
      debugPrint('FLAP-KEEPALIVE PASS held_s=${sw.elapsed.inSeconds}');
    },
    timeout: Timeout(Duration(seconds: idleSeconds + 90)),
  );
}
