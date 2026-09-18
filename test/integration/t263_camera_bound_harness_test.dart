// T26.3 evidence harness: the camera tool path, in-process, with real
// wall-clock waits and no phone, bridge or platform plugin.
//
// Wires the production stack (CameraVisionService -> ToolRegistry ->
// GatewayDeviceRpcReceiver) against a fake image_picker seam that reproduces
// the real `ImagePicker.pickImage` contract: a shot arrives after a delay, or
// never (the user closed the camera without taking one).
//
// The regression this proves gone: the registry's 10s default bound used to
// fire before the 20s capture window, so `camera_take_photo` died with
// `tool_timeout: ... within 10s` and a slow shot could never succeed. The
// 12s / 20s waits below ARE the evidence -- never shorten them with a fake
// clock.
//
// Env-gated because those waits are real wall-clock time and this harness must
// not slow the default suite (the tags alone do not exclude it, as this repo
// has no dart_test.yaml). Run it with:
//   FLAMES_T263_HARNESS=1 flutter test \
//     test/integration/t263_camera_bound_harness_test.dart --tags manual
@Tags(['manual', 'integration'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_ai_agent/data/datasources/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_connection_state.dart';
import 'package:flutter_ai_agent/domain/entities/gateway/gateway_message.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_client_base.dart';
import 'package:flutter_ai_agent/domain/services/gateway/gateway_rpc_receiver.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mocktail/mocktail.dart';

/// Platform seam fake for `ImagePicker.pickImage`.
class _FakeImagePicker extends Mock implements ImagePicker {}

class _FakeXFile extends Mock implements XFile {}

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
  _Harness({Duration? shotAfter})
      : picker = _FakeImagePicker(),
        client = _FakeGatewayClient() {
    final file = _FakeXFile();
    when(() => file.readAsBytes()).thenAnswer((_) async => _imageBytes);
    when(() => picker.retrieveLostData()).thenAnswer(
      (_) async => LostDataResponse.empty(),
    );
    when(
      () => picker.pickImage(
        source: any(named: 'source'),
        maxWidth: any(named: 'maxWidth'),
        maxHeight: any(named: 'maxHeight'),
        imageQuality: any(named: 'imageQuality'),
      ),
    ).thenAnswer((_) {
      final delay = shotAfter;
      if (delay == null) return Completer<XFile?>().future;
      return Future<XFile?>.delayed(delay, () => file);
    });

    // The REAL service with its production default capture window
    // (kCameraCaptureTimeout, 20s). Do not inject a shorter timeout: the whole
    // point is the production window.
    service = CameraVisionService(picker: picker);
    registry = ToolRegistry(cameraVisionService: service);
    receiver = GatewayDeviceRpcReceiver(
      gatewayClient: client,
      toolRegistry: registry,
    );
  }

  static final Uint8List _imageBytes =
      Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]);

  final _FakeImagePicker picker;
  final _FakeGatewayClient client;
  late final CameraVisionService service;
  late final ToolRegistry registry;
  late final GatewayDeviceRpcReceiver receiver;

  String get expectedBase64 => base64Encode(_imageBytes);
}

void main() {
  final harnessEnv = Platform.environment['FLAMES_T263_HARNESS'];
  final enabled = harnessEnv != null && harnessEnv.isNotEmpty;
  const skipMessage = 'set FLAMES_T263_HARNESS=1 to run this wall-clock '
      'camera bound harness (it waits ~32s of real time)';

  setUpAll(() {
    registerFallbackValue(ImageSource.camera);
  });

  group('T26.3 camera_take_photo answers through the tool path', () {
    test(
      'a shot taken after the old 10s bound still returns the image',
      skip: enabled ? false : skipMessage,
      () async {
        final harness = _Harness(shotAfter: const Duration(seconds: 12));
        addTearDown(harness.receiver.dispose);

        final stopwatch = Stopwatch()..start();
        final response = await harness.receiver.handleRequest(
          const GatewayToolCallRequestMessage(
            id: 'c1',
            tool: 'camera_take_photo',
            arguments: {'source': 'camera'},
          ),
        );
        stopwatch.stop();

        debugPrint(
          'T263 late_shot elapsed=${stopwatch.elapsed.inMilliseconds / 1000}s '
          'result=${response.error ?? 'image_ok'}',
        );

        expect(response.error, isNull);
        expect(
          jsonEncode(response.result),
          contains(harness.expectedBase64),
        );
        expect(harness.client.responses, hasLength(1));
        expect(harness.client.responses.single.callId, 'c1');
        expect(harness.client.responses.single.error, isNull);
        expect(stopwatch.elapsed, greaterThan(const Duration(seconds: 11)));
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 25)));
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    test(
      'a shot never taken reports the camera timeout, not the registry timeout',
      skip: enabled ? false : skipMessage,
      () async {
        final harness = _Harness();
        addTearDown(harness.receiver.dispose);

        final stopwatch = Stopwatch()..start();
        final response = await harness.receiver.handleRequest(
          const GatewayToolCallRequestMessage(
            id: 'c2',
            tool: 'camera_take_photo',
            arguments: {'source': 'camera'},
          ),
        );
        stopwatch.stop();

        debugPrint(
          'T263 no_shot elapsed=${stopwatch.elapsed.inMilliseconds / 1000}s '
          'result=${response.error}',
        );

        expect(stopwatch.elapsed, greaterThan(const Duration(seconds: 19)));
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 25)));
        expect(response.error, contains('camera_timeout'));
        expect(response.error, isNot(contains('tool_timeout')));
        expect(response.error, isNot(contains('within 10s')));
        expect(harness.client.responses.single.error, response.error);
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );

    test(
      'the registry bound is strictly above the capture window and under the '
      'bridge budget',
      skip: enabled ? false : skipMessage,
      () async {
        expect(
          ToolRegistry.longWindowToolTimeout > kCameraCaptureTimeout,
          isTrue,
          reason:
              'longWindowToolTimeout ${ToolRegistry.longWindowToolTimeout} '
              'must exceed the capture window $kCameraCaptureTimeout',
        );
        expect(
          ToolRegistry.longWindowToolTimeout < const Duration(seconds: 30),
          isTrue,
          reason:
              'longWindowToolTimeout ${ToolRegistry.longWindowToolTimeout} '
              'must stay under the device bridge 30s call budget',
        );

        final harness = _Harness(
          shotAfter: const Duration(milliseconds: 50),
        );
        addTearDown(harness.receiver.dispose);

        final response = await harness.receiver.handleRequest(
          const GatewayToolCallRequestMessage(
            id: 'c3',
            tool: 'camera_take_photo',
            arguments: {'source': 'camera'},
          ),
        );

        debugPrint(
          'T263 bound_check result=${response.error ?? 'image_ok'}',
        );

        expect(response.error, isNull);
        expect(
          jsonEncode(response.result),
          contains(harness.expectedBase64),
        );
      },
      timeout: const Timeout(Duration(seconds: 90)),
    );
  });
}
