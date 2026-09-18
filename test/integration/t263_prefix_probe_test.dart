// T26.3 pre-fix probe.
//
// This file deliberately avoids the post-fix constants (kCameraCaptureTimeout,
// kPiperPlaybackTimeout) so that it COMPILES against both the pre-fix tree and
// the post-fix tree. That is what makes it an assertion-level proof instead of
// a compile error.
//
// Run against the pre-fix tree (`git checkout 86eb0bc -- lib/`) it must fail
// with the "must not be left on the default bound" reason: both camera_take_photo
// and speak_text sat on the 10s registry default while their service-side
// windows were longer, so the registry's outer bound fired first and the tool's
// own honest error was unreachable. Against the fixed tree it passes.
//
// Do not delete this file: it is the proof that this class of bug cannot come
// back silently.
library;

import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_input_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockCameraVisionService extends Mock
    implements CameraVisionServiceBase {}

class _MockVoiceOutputService extends Mock implements VoiceOutputServiceBase {}

class _MockNfcService extends Mock implements NfcServiceBase {}

class _MockVoiceInputService extends Mock implements VoiceInputServiceBase {}

void main() {
  group('T26.3 pre-fix probe: every configurable-window tool declares its inner '
      'window', () {
    late ToolRegistry registry;

    setUp(() {
      registry = ToolRegistry(
        cameraVisionService: _MockCameraVisionService(),
        voiceOutputService: _MockVoiceOutputService(),
        nfcService: _MockNfcService(),
        voiceInputService: _MockVoiceInputService(),
      );
    });

    const configurableWindowTools = <String>[
      'camera_take_photo',
      'speak_text',
      'nfc_read_tag',
      'nfc_read_emoney_balance',
      'listen_voice_input',
    ];

    for (final name in configurableWindowTools) {
      test('$name declares an inner window and is not on the 10s default', () {
        final tool = registry.getTool(name);
        expect(tool, isNotNull, reason: '$name must be registered');

        expect(
          tool!.innerWindow,
          isNotNull,
          reason:
              '$name: an undeclared inner window means the registry\'s outer '
              'bound fires first and the tool\'s own honest error is '
              'unreachable',
        );
        expect(
          tool.effectiveTimeout > ToolRegistry.toolExecutionTimeout,
          isTrue,
          reason:
              '$name: effectiveTimeout ${tool.effectiveTimeout} must be greater '
              'than the 10s default bound, so the tool must not be left on the '
              'default bound',
        );
        expect(
          tool.effectiveTimeout < const Duration(seconds: 30),
          isTrue,
          reason:
              '$name: effectiveTimeout ${tool.effectiveTimeout} must stay under '
              'the device bridge 30s call budget',
        );
      });
    }
  });
}
