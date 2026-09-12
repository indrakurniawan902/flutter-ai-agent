import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/voice_waveform_widget.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late StreamController<double> soundLevelController;
  late StreamController<String> transcriptionController;
  bool stopAndSendCalled = false;
  bool cancelCalled = false;

  setUp(() {
    soundLevelController = StreamController<double>.broadcast();
    transcriptionController = StreamController<String>.broadcast();
    stopAndSendCalled = false;
    cancelCalled = false;
  });

  tearDown(() {
    soundLevelController.close();
    transcriptionController.close();
  });

  Widget createWidgetUnderTest({
    String initialText = '',
    bool isHoldToSpeak = false,
  }) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: VoiceWaveformWidget(
          soundLevelStream: soundLevelController.stream,
          transcriptionStream: transcriptionController.stream,
          initialText: initialText,
          isHoldToSpeak: isHoldToSpeak,
          onStopAndSend: () => stopAndSendCalled = true,
          onCancel: () => cancelCalled = true,
        ),
      ),
    );
  }

  testWidgets('VoiceWaveformWidget renders listening placeholder and buttons',
      (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());

    expect(find.byKey(const Key('voice_waveform_container')), findsOneWidget);
    expect(find.text('Listening... speak now'), findsOneWidget);
    expect(
      find.byKey(const Key('voice_waveform_cancel_button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('voice_waveform_send_button')),
      findsOneWidget,
    );
  });

  testWidgets(
      'VoiceWaveformWidget updates transcribed text dynamically from stream',
      (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());

    transcriptionController.add('Buka kalender saya');
    await tester.pump();

    expect(find.text('Buka kalender saya'), findsOneWidget);

    transcriptionController.add('Buka kalender saya besok pagi');
    await tester.pump();

    expect(find.text('Buka kalender saya besok pagi'), findsOneWidget);
  });

  testWidgets('VoiceWaveformWidget animates bars on sound level changes',
      (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());

    expect(find.byKey(const Key('voice_waveform_bars')), findsOneWidget);

    soundLevelController.add(0.85);
    await tester.pump();

    expect(find.byKey(const Key('voice_waveform_bars')), findsOneWidget);
  });

  testWidgets('VoiceWaveformWidget tapping send button invokes onStopAndSend',
      (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());

    await tester.tap(find.byKey(const Key('voice_waveform_send_button')));
    await tester.pump();

    expect(stopAndSendCalled, true);
    expect(cancelCalled, false);
  });

  testWidgets('VoiceWaveformWidget tapping cancel button invokes onCancel',
      (tester) async {
    await tester.pumpWidget(createWidgetUnderTest());

    await tester.tap(find.byKey(const Key('voice_waveform_cancel_button')));
    await tester.pump();

    expect(cancelCalled, true);
    expect(stopAndSendCalled, false);
  });

  testWidgets('VoiceWaveformWidget shows hold-to-speak hint when in hold mode',
      (tester) async {
    await tester.pumpWidget(createWidgetUnderTest(isHoldToSpeak: true));

    expect(find.text('Release mic to send'), findsOneWidget);
  });
}
