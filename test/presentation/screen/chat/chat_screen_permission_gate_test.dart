import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/tools/chat/camera_vision_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/cubit/agent_state.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/app_settings_opener.dart';
import 'package:flutter_ai_agent/utils/permission_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../helpers/mocks.dart';

class _MockPermissionRequester extends Mock implements PermissionRequester {}

class _FakeAppSettingsOpener implements AppSettingsOpener {
  int calls = 0;

  @override
  Future<bool> openAppSettings() async {
    calls++;
    return true;
  }
}

void main() {
  late MockAgentCubit mockAgentCubit;
  late MockVoiceInputService mockVoiceService;
  late MockVoiceOutputService mockVoiceOutputService;
  late MockCameraVisionService mockCameraService;

  final capturedBase64 = base64Encode(utf8.encode('captured-image-bytes'));

  setUpAll(() {
    registerFallbackValue(Permission.microphone);
    registerFallbackValue(Permission.camera);
    registerFallbackValue(CameraSource.camera);
  });

  setUp(() async {
    await sl.reset();
    mockAgentCubit = MockAgentCubit();
    mockVoiceService = MockVoiceInputService();
    mockVoiceOutputService = MockVoiceOutputService();
    mockCameraService = MockCameraVisionService();

    when(() => mockAgentCubit.state).thenReturn(const AgentIdle());
    when(() => mockAgentCubit.messages).thenReturn([]);
    when(() => mockAgentCubit.activeSessionTitle).thenReturn('New chat');
    when(() => mockAgentCubit.stream).thenAnswer((_) => const Stream.empty());
    when(() => mockAgentCubit.stop()).thenAnswer((_) async {});
    when(() => mockAgentCubit.sendMessage(any())).thenAnswer((_) async {});
    when(() => mockAgentCubit.activeSessionTitle).thenReturn('New chat');

    when(() => mockVoiceService.transcriptionStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceService.soundLevelStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceService.statusStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceService.errorStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceService.lastRecognizedWords).thenReturn('');
    when(() => mockVoiceService.isListening).thenReturn(false);
    when(() => mockVoiceService.isAvailable).thenReturn(true);
    when(() => mockVoiceService.dispose()).thenReturn(null);
    when(() => mockVoiceService.cancelListening()).thenAnswer((_) async {});
    when(() => mockVoiceService.stopListening())
        .thenAnswer((_) async => const Right(''));

    when(() => mockVoiceOutputService.isMuted).thenReturn(false);
    when(() => mockVoiceOutputService.interrupt()).thenAnswer((_) async {});
    when(() => mockVoiceOutputService.statusStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceOutputService.errorStream)
        .thenAnswer((_) => const Stream.empty());
    when(() => mockVoiceOutputService.dispose()).thenReturn(null);

    sl.registerFactory<AgentCubit>(() => mockAgentCubit);
    sl.registerFactory<CameraVisionServiceBase>(() => mockCameraService);
  });

  tearDown(() async {
    await sl.reset();
  });

  Widget createWidgetUnderTest(PermissionGate gate) {
    return MaterialApp(
      home: ChatScreen(
        permissionGate: gate,
        voiceInputService: mockVoiceService,
        voiceOutputService: mockVoiceOutputService,
      ),
    );
  }

  PermissionGate gateWith(
    PermissionStatus status, {
    _FakeAppSettingsOpener? opener,
    PermissionStatus? requestResult,
  }) {
    final requester = _MockPermissionRequester();
    when(() => requester.checkStatus(any())).thenAnswer((_) async => status);
    when(() => requester.requestPermission(any())).thenAnswer(
      (_) async => requestResult ?? status,
    );
    return PermissionGate(requester: requester, settingsOpener: opener);
  }

  group('ChatScreen - microphone JIT permission gate', () {
    testWidgets('granted → no modal and voice service starts', (tester) async {
      when(() => mockVoiceService.startListening())
          .thenAnswer((_) async => const Right(unit));

      await tester.pumpWidget(
        createWidgetUnderTest(gateWith(PermissionStatus.granted)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_mic_button')));
      await tester.pump();

      expect(
        find.byKey(const Key('permission_rationale_allow_btn')),
        findsNothing,
      );
      verify(() => mockVoiceService.startListening()).called(1);
    });

    testWidgets('denied → rationale modal, Not Now aborts listening',
        (tester) async {
      await tester.pumpWidget(
        createWidgetUnderTest(gateWith(PermissionStatus.denied)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_mic_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permission_rationale_allow_btn')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('permission_rationale_not_now_btn')),
      );
      await tester.pumpAndSettle();

      verifyNever(() => mockVoiceService.startListening());
    });

    testWidgets(
        'permanentlyDenied → notice + Buka Pengaturan opens settings and aborts',
        (tester) async {
      final opener = _FakeAppSettingsOpener();
      await tester.pumpWidget(
        createWidgetUnderTest(
          gateWith(PermissionStatus.permanentlyDenied, opener: opener),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('chat_mic_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permission_rationale_permanently_denied_notice')),
        findsOneWidget,
      );
      final allowBtn = find.byKey(const Key('permission_rationale_allow_btn'));
      expect(allowBtn, findsOneWidget);
      expect(
        find.descendant(of: allowBtn, matching: find.text('Buka Pengaturan')),
        findsOneWidget,
      );

      await tester.tap(allowBtn);
      await tester.pumpAndSettle();

      expect(opener.calls, 1);
      verifyNever(() => mockVoiceService.startListening());
    });
  });

  group('ChatScreen - camera JIT permission gate', () {
    Future<void> openCameraSheet(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('chat_attach_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('chat_attach_camera')));
      await tester.pumpAndSettle();
    }

    testWidgets('granted → no modal and camera service captures', (tester) async {
      when(() => mockCameraService.takePhoto(source: CameraSource.camera))
          .thenAnswer((_) async => Right(capturedBase64));

      await tester.pumpWidget(
        createWidgetUnderTest(gateWith(PermissionStatus.granted)),
      );
      await tester.pumpAndSettle();

      await openCameraSheet(tester);

      expect(
        find.byKey(const Key('permission_rationale_allow_btn')),
        findsNothing,
      );
      verify(
        () => mockCameraService.takePhoto(source: CameraSource.camera),
      ).called(1);
    });

    testWidgets('denied → rationale modal, Not Now aborts capture',
        (tester) async {
      await tester.pumpWidget(
        createWidgetUnderTest(gateWith(PermissionStatus.denied)),
      );
      await tester.pumpAndSettle();

      await openCameraSheet(tester);

      expect(
        find.byKey(const Key('permission_rationale_allow_btn')),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(const Key('permission_rationale_not_now_btn')),
      );
      await tester.pumpAndSettle();

      verifyNever(
        () => mockCameraService.takePhoto(source: any(named: 'source')),
      );
    });

    testWidgets(
        'permanentlyDenied → notice + Buka Pengaturan opens settings and aborts',
        (tester) async {
      final opener = _FakeAppSettingsOpener();
      await tester.pumpWidget(
        createWidgetUnderTest(
          gateWith(PermissionStatus.permanentlyDenied, opener: opener),
        ),
      );
      await tester.pumpAndSettle();

      await openCameraSheet(tester);

      expect(
        find.byKey(const Key('permission_rationale_permanently_denied_notice')),
        findsOneWidget,
      );
      final allowBtn = find.byKey(const Key('permission_rationale_allow_btn'));
      expect(
        find.descendant(of: allowBtn, matching: find.text('Buka Pengaturan')),
        findsOneWidget,
      );

      await tester.tap(allowBtn);
      await tester.pumpAndSettle();

      expect(opener.calls, 1);
      verifyNever(
        () => mockCameraService.takePhoto(source: any(named: 'source')),
      );
    });
  });

  testWidgets(
      'return-from-settings banner re-checks status and opens settings',
      (tester) async {
    final requester = _MockPermissionRequester();
    final opener = _FakeAppSettingsOpener();
    when(() => requester.checkStatus(any()))
        .thenAnswer((_) async => PermissionStatus.denied);
    final gate = PermissionGate(requester: requester, settingsOpener: opener);

    await tester.pumpWidget(createWidgetUnderTest(gate));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('permission_status_banner')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('permission_banner_open_settings')));
    await tester.pumpAndSettle();
    expect(opener.calls, 1);

    await tester.tap(find.byKey(const Key('permission_banner_dismiss')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('permission_status_banner')),
      findsNothing,
    );

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    verify(() => requester.checkStatus(any())).called(greaterThan(2));
  });
}
