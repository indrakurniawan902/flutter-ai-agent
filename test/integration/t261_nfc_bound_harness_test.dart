// T26.1 evidence harness: the NFC tool path, in-process, with real wall-clock
// waits and no phone, bridge or platform plugin.
//
// Wires the production stack (NfcService -> ToolRegistry ->
// GatewayDeviceRpcReceiver) against a fake platform seam that reproduces the
// real `DefaultNfcPlatformWrapper.runWithCard` contract: wait for a card, and
// when none arrives throw `TimeoutException('NFC scan timed out', timeout)`.
//
// The regression this proves gone: the registry's 10s default bound used to
// fire before the 20s NFC scan window, so `nfc_read_tag` died with
// `tool_timeout: ... within 10s` and a tap could never succeed. The 12s / 20s
// waits below ARE the evidence -- never shorten them with a fake clock.
//
// Env-gated because those waits are real wall-clock time and this harness must
// not slow the default suite (the tags alone do not exclude it, as this repo
// has no dart_test.yaml). Run it with:
//   FLAMES_T261_HARNESS=1 flutter test \
//     test/integration/t261_nfc_bound_harness_test.dart --tags manual
@Tags(['manual', 'integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_agent/data/datasources/tools/device/nfc_service.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Platform seam fake. [cardAfter] = card arrival delay; null means no card is
/// ever tapped, so the call waits [timeout] and throws exactly like
/// `DefaultNfcPlatformWrapper`.
class _FakeNfcPlatform implements NfcPlatformWrapper {
  _FakeNfcPlatform({this.cardAfter});

  final Duration? cardAfter;

  /// Every `timeout` the production service (or its wrapper default) supplied.
  final List<Duration> recordedTimeouts = <Duration>[];

  static final Uint8List _uid =
      Uint8List.fromList(<int>[0x04, 0xa1, 0xb2, 0xc3]);

  RawNfcCard _card() => RawNfcCard(
        uid: _uid,
        techList: const <String>['android.nfc.tech.IsoDep'],
        transceive: (apdu) async {
          // SELECT by AID succeeds; any other APDU answers the balance payload
          // (25000 rupiah big-endian) followed by SW 90 00.
          if (apdu.length > 1 && apdu[1] == 0xA4) {
            return Uint8List.fromList(<int>[0x90, 0x00]);
          }
          return Uint8List.fromList(
            <int>[0x00, 0x00, 0x61, 0xA8, 0x90, 0x00],
          );
        },
      );

  @override
  Future<String> availability() async => 'enabled';

  @override
  Future<T> runWithCard<T>({
    required Set<String> pollingOptions,
    Duration timeout = kNfcScanTimeout,
    required Future<T> Function(RawNfcCard card) action,
  }) async {
    recordedTimeouts.add(timeout);
    final delay = cardAfter;
    if (delay != null) {
      await Future<void>.delayed(delay);
      return action(_card());
    }
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

class _CapturedResponse {
  const _CapturedResponse({required this.callId, this.result, this.error});

  final String callId;
  final Map<String, dynamic>? result;
  final String? error;
}

/// Transport fake: only the members [GatewayDeviceRpcReceiver] touches are
/// real, the rest are deliberately unimplemented.
class _FakeGatewayClient implements GatewayClientBase {
  final List<_CapturedResponse> responses = <_CapturedResponse>[];

  @override
  Stream<GatewayToolCallRequestMessage> get toolCallRequestStream =>
      const Stream<GatewayToolCallRequestMessage>.empty();

  @override
  void sendToolCallResponse({
    required String callId,
    Map<String, dynamic>? result,
    String? error,
  }) {
    responses.add(
      _CapturedResponse(callId: callId, result: result, error: error),
    );
  }

  @override
  Future<void> dispose() async {}

  @override
  GatewayConnectionState get state => throw UnimplementedError();

  @override
  Stream<GatewayConnectionState> get stateStream => throw UnimplementedError();

  @override
  Stream<GatewayMessage> get messageStream => throw UnimplementedError();

  @override
  Stream<GatewayTextDeltaMessage> get textDeltaStream =>
      throw UnimplementedError();

  @override
  Stream<GatewayElicitationRequestMessage> get elicitationRequestStream =>
      throw UnimplementedError();

  @override
  Future<void> connect(String gatewayUrl, {String? token}) =>
      throw UnimplementedError();

  @override
  Future<void> connectWithProfile(ServerProfile profile) =>
      throw UnimplementedError();

  @override
  void send(GatewayMessage message) => throw UnimplementedError();

  @override
  void sendJson(Map<String, dynamic> json) => throw UnimplementedError();

  @override
  void sendElicitationResponse({
    required String requestId,
    required bool approved,
    bool biometricVerified = false,
  }) =>
      throw UnimplementedError();

  @override
  void sendChatMessage(
    String content, {
    String role = 'user',
    Map<String, dynamic>? metadata,
  }) =>
      throw UnimplementedError();

  @override
  void sendChatCancel() => throw UnimplementedError();

  @override
  Future<void> disconnect({String? reason}) => throw UnimplementedError();
}

class _Harness {
  _Harness({Duration? cardAfter})
      : platform = _FakeNfcPlatform(cardAfter: cardAfter),
        client = _FakeGatewayClient() {
    registry = ToolRegistry(
      nfcService: NfcService(platformWrapper: platform),
    );
    receiver = GatewayDeviceRpcReceiver(
      gatewayClient: client,
      toolRegistry: registry,
    );
  }

  final _FakeNfcPlatform platform;
  final _FakeGatewayClient client;
  late final ToolRegistry registry;
  late final GatewayDeviceRpcReceiver receiver;
}

void main() {
  final harnessEnv = Platform.environment['FLAMES_T261_HARNESS'];
  final enabled = harnessEnv != null && harnessEnv.isNotEmpty;
  const skipMessage = 'set FLAMES_T261_HARNESS=1 to run this wall-clock NFC '
      'bound harness (it waits 12s/20s in real time)';

  group('T26.1 NFC tools answer through the tool path', () {
    test(
      'a card presented after the old 10s bound still returns its UID',
      skip: enabled ? false : skipMessage,
      () async {
        final harness = _Harness(cardAfter: const Duration(seconds: 12));
        addTearDown(harness.receiver.dispose);

        final stopwatch = Stopwatch()..start();
        final response = await harness.receiver.handleRequest(
          const GatewayToolCallRequestMessage(
            id: 'c1',
            tool: 'nfc_read_tag',
          ),
        );
        stopwatch.stop();

        debugPrint(
          'T261 late_card elapsed=${stopwatch.elapsed.inMilliseconds / 1000}s '
          'result=${response.error ?? response.result}',
        );

        expect(response.error, isNull);
        expect(jsonEncode(response.result), contains('04a1b2c3'));
        expect(harness.client.responses, hasLength(1));
        expect(harness.client.responses.single.callId, 'c1');
        expect(harness.client.responses.single.error, isNull);
        expect(stopwatch.elapsed, greaterThan(const Duration(seconds: 11)));
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 25)));
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    test(
      'no card tapped reports the device timeout, not the registry timeout',
      skip: enabled ? false : skipMessage,
      () async {
        final harness = _Harness();
        addTearDown(harness.receiver.dispose);

        final stopwatch = Stopwatch()..start();
        final response = await harness.receiver.handleRequest(
          const GatewayToolCallRequestMessage(
            id: 'c2',
            tool: 'nfc_read_tag',
          ),
        );
        stopwatch.stop();

        debugPrint(
          'T261 no_card elapsed=${stopwatch.elapsed.inMilliseconds / 1000}s '
          'result=${response.error}',
        );

        expect(stopwatch.elapsed, greaterThan(const Duration(seconds: 19)));
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 25)));
        expect(response.error, contains('NFC scan timed out'));
        expect(response.error, isNot(contains('tool_timeout')));
        expect(response.error, isNot(contains('within 10s')));
        expect(harness.client.responses.single.error, response.error);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    test(
      'no card tapped on the e-money tool reports the device timeout',
      skip: enabled ? false : skipMessage,
      () async {
        final harness = _Harness();
        addTearDown(harness.receiver.dispose);

        final stopwatch = Stopwatch()..start();
        final response = await harness.receiver.handleRequest(
          const GatewayToolCallRequestMessage(
            id: 'c3',
            tool: 'nfc_read_emoney_balance',
          ),
        );
        stopwatch.stop();

        debugPrint(
          'T261 emoney_no_card '
          'elapsed=${stopwatch.elapsed.inMilliseconds / 1000}s '
          'result=${response.error}',
        );

        expect(stopwatch.elapsed, greaterThan(const Duration(seconds: 19)));
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 25)));
        expect(response.error, contains('NFC scan timed out'));
        expect(response.error, isNot(contains('tool_timeout')));
        expect(response.error, isNot(contains('within 10s')));
        expect(harness.client.responses.single.error, response.error);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    test(
      'the registry bound is strictly above the scan window',
      skip: enabled ? false : skipMessage,
      () async {
        expect(
          ToolRegistry.longWindowToolTimeout > kNfcScanTimeout,
          isTrue,
          reason:
              'longWindowToolTimeout ${ToolRegistry.longWindowToolTimeout} '
              'must exceed the scan window $kNfcScanTimeout',
        );

        final harness = _Harness(
          cardAfter: const Duration(milliseconds: 50),
        );
        addTearDown(harness.receiver.dispose);

        final response = await harness.receiver.handleRequest(
          const GatewayToolCallRequestMessage(
            id: 'c4',
            tool: 'nfc_read_tag',
          ),
        );

        debugPrint(
          'T261 bound_check result=${response.error ?? response.result} '
          'wrapper_timeout=${harness.platform.recordedTimeouts.last}',
        );

        expect(response.error, isNull);
        expect(harness.platform.recordedTimeouts, isNotEmpty);
        expect(harness.platform.recordedTimeouts.last, kNfcScanTimeout);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
