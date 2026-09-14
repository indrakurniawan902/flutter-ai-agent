import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/tools/chat/voice_output_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Regression guard for the T19.7 independent-review finding: resolving the
  // voice output graph from DI must not construct a native `AudioPlayer` or
  // `FlutterTts`. Those constructors schedule unawaited MethodChannel traffic
  // that a test host cannot answer. The handlers below RECORD calls instead of
  // swallowing them, so a regression fails the assertion instead of being
  // hidden behind a no-op stub.
  const channels = <String>[
    'xyz.luan/audioplayers.global',
    'xyz.luan/audioplayers',
    'flutter_tts',
  ];

  late List<MethodCall> calls;

  setUp(() async {
    calls = <MethodCall>[];
    await sl.reset();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), (call) async {
        calls.add(call);
        return null;
      });
    }
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final name in channels) {
      messenger.setMockMethodCallHandler(MethodChannel(name), null);
    }
    await sl.reset();
  });

  test('DI resolution of VoiceOutputServiceBase builds no native audio player',
      () async {
    await initDependencies();

    final service = sl<VoiceOutputServiceBase>();
    expect(service, isA<VoiceOutputServiceBase>());

    // Let any unawaited plugin init run; there must be none.
    await Future<void>.delayed(const Duration(milliseconds: 250));

    expect(
      calls,
      isEmpty,
      reason: 'DI resolution must not touch the audioplayers / flutter_tts '
          'plugin channels (lazy AudioPlayer + lazy FlutterTts).',
    );
  });
}
