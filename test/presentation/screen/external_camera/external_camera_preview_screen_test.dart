import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/tools/chat/external_camera_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/permission_rationale_modal.dart';
import 'package:flutter_ai_agent/presentation/screen/external_camera/cubit/external_camera_preview_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/external_camera/cubit/external_camera_preview_state.dart';
import 'package:flutter_ai_agent/presentation/screen/external_camera/external_camera_preview_screen.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/utils/permission_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';

class MockExternalCameraService extends Mock
    implements ExternalCameraServiceBase {}

class _MockPermissionRequester extends Mock implements PermissionRequester {}

const _device = ExternalCameraDevice(
  deviceId: 7,
  name: 'USB Camera',
  vendorId: 0x2BC5,
  productId: 0x0609,
);

const _mode = ExternalCameraPreviewMode(
  width: 1280,
  height: 720,
  fps: 30,
  formatName: 'MJPEG',
);

const _textureId = 4242;

const _pngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

const _frame = ExternalCameraFrame(
  width: 640,
  height: 480,
  base64Jpeg: _pngBase64,
);

void main() {
  late MockExternalCameraService service;
  late StreamController<ExternalCameraDeviceEvent> events;

  setUpAll(() {
    registerFallbackValue(0);
    registerFallbackValue(Permission.camera);
  });

  setUp(() {
    service = MockExternalCameraService();
    events = StreamController<ExternalCameraDeviceEvent>.broadcast();
    when(() => service.deviceEvents).thenAnswer((_) => events.stream);
    when(
      () => service.status,
    ).thenAnswer((_) => const ExternalCameraStatus.closed());
  });

  tearDown(() async {
    await events.close();
  });

  ExternalCameraPreviewCubit buildCubit({
    Future<bool> Function()? ensureCameraPermission,
  }) {
    return ExternalCameraPreviewCubit(
      service: service,
      ensureCameraPermission: ensureCameraPermission ?? () async => true,
    );
  }

  Widget wrap(
    ExternalCameraPreviewCubit cubit, {
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      theme: HermesTheme.darkTheme,
      home: ExternalCameraPreviewScreen(cubit: cubit),
    );
  }

  void stubHappyPath() {
    when(() => service.listDevices()).thenAnswer(
      (_) async => const Right<Failure, List<ExternalCameraDevice>>([_device]),
    );
    when(
      () => service.openDevice(
        _device.deviceId,
        ensureCameraPermission: any(named: 'ensureCameraPermission'),
      ),
    ).thenAnswer(
      (_) async => const Right<Failure, ExternalCameraPreviewMode>(_mode),
    );
    when(
      () => service.createPreviewTexture(),
    ).thenAnswer((_) async => const Right<Failure, int>(_textureId));
    when(
      () => service.attachPreviewTexture(
        _textureId,
        width: any(named: 'width'),
        height: any(named: 'height'),
      ),
    ).thenAnswer((_) async => const Right(null));
    when(
      () => service.disposePreviewTexture(any()),
    ).thenAnswer((_) async => const Right(null));
    when(() => service.closeDevice()).thenAnswer((_) async {});
  }

  Future<ExternalCameraPreviewCubit> pumpPreviewing(
    WidgetTester tester, {
    GlobalKey<NavigatorState>? navigatorKey,
  }) async {
    final cubit = buildCubit();
    await cubit.loadDevices();
    await tester.pumpWidget(wrap(cubit, navigatorKey: navigatorKey));
    await tester.pump();
    return cubit;
  }

  // Bounded pumps: the screen shows a CircularProgressIndicator while it is
  // loading or starting, and that animation never settles, so pumpAndSettle
  // would hang until the 10-minute test timeout.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  // BlocProvider.value never closes an injected cubit, so the test closes it
  // explicitly to run the same teardown a provider-owned cubit gets.
  Future<void> disposeScreen(
    WidgetTester tester,
    ExternalCameraPreviewCubit cubit,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await settle(tester);
    await tester.runAsync(() => cubit.close());
  }

  testWidgets(
    'renders the no-device pane with a refresh action and no eternal spinner',
    (tester) async {
      when(() => service.listDevices()).thenAnswer(
        (_) async => const Right<Failure, List<ExternalCameraDevice>>(
          <ExternalCameraDevice>[],
        ),
      );
      final cubit = buildCubit();
      await cubit.loadDevices();

      await tester.pumpWidget(wrap(cubit));
      await tester.pump();

      expect(find.byKey(const Key('external_camera_no_device')), findsOneWidget);
      expect(
        find.byKey(const Key('external_camera_refresh_button')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byKey(const Key('external_camera_refresh_button')));
      await settle(tester);

      verify(() => service.listDevices()).called(2);

      await disposeScreen(tester, cubit);
    },
  );

  testWidgets(
    'renders the permission-denied pane when the camera permission is refused',
    (tester) async {
      final requester = _MockPermissionRequester();
      var statusCalls = 0;
      when(() => requester.checkStatus(any())).thenAnswer((_) async {
        statusCalls++;
        return statusCalls == 1
            ? PermissionStatus.denied
            : PermissionStatus.granted;
      });
      when(
        () => requester.requestPermission(any()),
      ).thenAnswer((_) async => PermissionStatus.denied);
      final gate = PermissionGate(requester: requester);
      final navigatorKey = GlobalKey<NavigatorState>();

      when(() => service.listDevices()).thenAnswer(
        (_) async =>
            const Right<Failure, List<ExternalCameraDevice>>([_device]),
      );
      var openCalls = 0;
      when(
        () => service.openDevice(
          _device.deviceId,
          ensureCameraPermission: any(named: 'ensureCameraPermission'),
        ),
      ).thenAnswer((invocation) async {
        openCalls++;
        final ensure = invocation.namedArguments[#ensureCameraPermission]
            as Future<bool> Function();
        await ensure();
        return openCalls == 1
            ? const Left<Failure, ExternalCameraPreviewMode>(
                PermissionFailure('denied'),
              )
            : const Right<Failure, ExternalCameraPreviewMode>(_mode);
      });
      when(
        () => service.createPreviewTexture(),
      ).thenAnswer((_) async => const Right<Failure, int>(_textureId));
      when(
        () => service.attachPreviewTexture(
          _textureId,
          width: any(named: 'width'),
          height: any(named: 'height'),
        ),
      ).thenAnswer((_) async => const Right(null));

      final cubit = buildCubit(
        ensureCameraPermission: () => gate.requestWithRationale(
          navigatorKey.currentContext!,
          PermissionRationaleType.camera,
        ),
      );

      await tester.pumpWidget(wrap(cubit, navigatorKey: navigatorKey));

      final load = cubit.loadDevices();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(const Key('permission_rationale_allow_btn')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('permission_rationale_allow_btn')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await load;
      await settle(tester);

      expect(
        find.byKey(const Key('external_camera_permission_denied')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('external_camera_grant_button')),
        findsOneWidget,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // Note: mocktail's verify only counts calls that are not already
      // verified, so a `.called(1)` here would consume the call the cumulative
      // `.called(2)` assertions at the end of this test rely on.
      verify(() => requester.requestPermission(any())).called(1);

      await tester.tap(find.byKey(const Key('external_camera_grant_button')));
      await settle(tester);

      expect(cubit.state.status, ExternalCameraPreviewStatus.previewing);
      expect(
        find.byKey(const Key('external_camera_preview_texture')),
        findsOneWidget,
      );

      verify(
        () => service.openDevice(
          _device.deviceId,
          ensureCameraPermission: any(named: 'ensureCameraPermission'),
        ),
      ).called(2);
      verify(() => requester.checkStatus(any())).called(2);

      await disposeScreen(tester, cubit);
    },
  );

  testWidgets(
    'renders the live preview with a texture sized from the negotiated mode',
    (tester) async {
      stubHappyPath();
      final cubit = await pumpPreviewing(tester);

      expect(
        find.byKey(const Key('external_camera_preview_texture')),
        findsOneWidget,
      );
      final texture = tester.widget<Texture>(
        find.byKey(const Key('external_camera_preview_texture')),
      );
      expect(texture.textureId, _textureId);

      final aspectFinder = find.ancestor(
        of: find.byKey(const Key('external_camera_preview_texture')),
        matching: find.byType(AspectRatio),
      );
      expect(aspectFinder, findsOneWidget);
      expect(
        tester.widget<AspectRatio>(aspectFinder).aspectRatio,
        _mode.width / _mode.height,
      );

      verify(
        () => service.attachPreviewTexture(
          _textureId,
          width: _mode.width,
          height: _mode.height,
        ),
      ).called(1);

      final captureButton = find.byKey(
        const Key('external_camera_capture_button'),
      );
      expect(captureButton, findsOneWidget);
      expect(tester.widget<FilledButton>(captureButton).onPressed, isNotNull);

      await disposeScreen(tester, cubit);
    },
  );

  testWidgets(
    'capture shows the still and a failed capture keeps the capture action usable',
    (tester) async {
      // A phone-sized viewport: at the 800x600 default the captured still
      // legitimately sits below the fold of the scrolling pane, so the lazy
      // ListView would not build it yet.
      await tester.binding.setSurfaceSize(const Size(400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      stubHappyPath();
      when(() => service.capture(quality: any(named: 'quality'))).thenAnswer(
        (_) async => const Right<Failure, ExternalCameraFrame>(_frame),
      );
      final cubit = await pumpPreviewing(tester);

      final captureButton = find.byKey(
        const Key('external_camera_capture_button'),
      );
      await tester.ensureVisible(captureButton);
      await settle(tester);
      await tester.tap(captureButton);
      await settle(tester);

      expect(
        find.byKey(const Key('external_camera_captured_image')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('external_camera_retake_button')),
        findsOneWidget,
      );

      when(() => service.capture(quality: any(named: 'quality'))).thenAnswer(
        (_) async =>
            const Left<Failure, ExternalCameraFrame>(CameraTimeoutFailure()),
      );

      final retakeButton = find.byKey(
        const Key('external_camera_retake_button'),
      );
      await tester.ensureVisible(retakeButton);
      await settle(tester);
      await tester.tap(retakeButton);
      await settle(tester);

      expect(
        find.byKey(const Key('external_camera_capture_failed')),
        findsOneWidget,
      );
      expect(tester.widget<FilledButton>(captureButton).onPressed, isNotNull);

      await tester.ensureVisible(captureButton);
      await settle(tester);
      await tester.tap(captureButton);
      await settle(tester);

      verify(() => service.capture(quality: any(named: 'quality'))).called(3);

      await disposeScreen(tester, cubit);
    },
  );

  testWidgets('releases the preview texture when the screen is disposed', (
    tester,
  ) async {
    stubHappyPath();
    final cubit = await pumpPreviewing(tester);

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await settle(tester);
    await tester.runAsync(() => cubit.close());

    verify(() => service.disposePreviewTexture(_textureId)).called(1);
    verify(() => service.closeDevice()).called(1);
  });

  testWidgets('a device detach during preview shows a message and does not throw', (
    tester,
  ) async {
    stubHappyPath();
    final cubit = await pumpPreviewing(tester);

    events.add(
      const ExternalCameraDeviceEvent(
        type: ExternalCameraDeviceEventType.detached,
        device: _device,
      ),
    );
    await settle(tester);

    expect(find.byKey(const Key('external_camera_detached')), findsOneWidget);
    expect(find.text('The external camera was disconnected.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    verify(() => service.disposePreviewTexture(_textureId)).called(1);
    verify(() => service.closeDevice()).called(1);

    await disposeScreen(tester, cubit);
  });

  testWidgets('disposing the screen after a detach does not throw', (
    tester,
  ) async {
    stubHappyPath();
    final cubit = await pumpPreviewing(tester);

    events.add(
      const ExternalCameraDeviceEvent(
        type: ExternalCameraDeviceEventType.detached,
        device: _device,
      ),
    );
    await settle(tester);

    await disposeScreen(tester, cubit);

    expect(tester.takeException(), isNull);
    verify(() => service.disposePreviewTexture(_textureId)).called(1);
  });
}
