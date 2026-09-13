import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/app_settings_opener.dart';
import 'package:flutter_ai_agent/presentation/screen/pairing/qr_scanner_screen.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_ai_agent/utils/permission_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:permission_handler/permission_handler.dart';

class _FakePermissionRequester implements PermissionRequester {
  PermissionStatus status;
  PermissionStatus? requestResult;
  int checkCount = 0;
  int requestCount = 0;
  Completer<PermissionStatus>? pendingCheck;

  _FakePermissionRequester({
    required this.status,
    this.requestResult,
    this.pendingCheck,
  });

  @override
  Future<PermissionStatus> checkStatus(Permission permission) async {
    checkCount++;
    if (pendingCheck != null) {
      return pendingCheck!.future;
    }
    return status;
  }

  @override
  Future<PermissionStatus> requestPermission(Permission permission) async {
    requestCount++;
    return requestResult ?? status;
  }
}

class _FakeAppSettingsOpener implements AppSettingsOpener {
  int calls = 0;

  @override
  Future<bool> openAppSettings() async {
    calls++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fakeScannerKey = Key('fake_scanner_widget');

  Widget buildTestWidget({
    required PermissionGate gate,
    Widget Function(BuildContext, void Function(String))? scannerWidgetBuilder,
  }) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: QrScannerScreen(
        permissionGate: gate,
        scannerWidgetBuilder: scannerWidgetBuilder ??
            (context, onDetect) => Container(
                  key: fakeScannerKey,
                  color: Colors.blueGrey,
                ),
      ),
    );
  }

  group('QrScannerScreen - Camera Permission 3-State Sweep', () {
    testWidgets(
      'state: granted → fake scanner present, denied UI and rationale modal absent',
      (tester) async {
        final requester = _FakePermissionRequester(
          status: PermissionStatus.granted,
        );
        final opener = _FakeAppSettingsOpener();
        final gate = PermissionGate(
          requester: requester,
          settingsOpener: opener,
        );

        await tester.pumpWidget(buildTestWidget(gate: gate));
        await tester.pumpAndSettle();

        expect(find.byKey(fakeScannerKey), findsOneWidget);
        expect(
          find.byKey(const Key('qr_camera_grant_button')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('permission_rationale_allow_btn')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('qr_viewfinder_overlay')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'state: denied → friendly denied state shown, tapping CTA opens rationale modal, manual input works',
      (tester) async {
        final requester = _FakePermissionRequester(
          status: PermissionStatus.denied,
          requestResult: PermissionStatus.granted,
        );
        final opener = _FakeAppSettingsOpener();
        final gate = PermissionGate(
          requester: requester,
          settingsOpener: opener,
        );

        await tester.pumpWidget(buildTestWidget(gate: gate));
        await tester.pumpAndSettle();

        // 1. Fake scanner must NOT be visible
        expect(find.byKey(fakeScannerKey), findsNothing);

        // 2. Denied state UI must be visible
        expect(
          find.byKey(const Key('qr_camera_grant_button')),
          findsOneWidget,
        );
        expect(
          find.text('Akses kamera diperlukan untuk memindai QR pairing'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('permission_rationale_permanently_denied_notice')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('qr_camera_open_settings_button')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('qr_viewfinder_overlay')),
          findsNothing,
        );

        // 3. Manual input fallback still works
        expect(
          find.byKey(const Key('qr_manual_input_button')),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('qr_manual_input_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('manual_input_dialog')), findsOneWidget);
        await tester.tap(find.byKey(const Key('manual_input_cancel_button')));
        await tester.pumpAndSettle();

        // 4. Tapping CTA opens rationale modal
        await tester.tap(find.byKey(const Key('qr_camera_grant_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('permission_rationale_allow_btn')),
          findsOneWidget,
        );

        // 5. Allowing in rationale modal grants permission and shows scanner
        requester.status = PermissionStatus.granted;
        await tester.tap(find.byKey(const Key('permission_rationale_allow_btn')));
        await tester.pumpAndSettle();

        expect(find.byKey(fakeScannerKey), findsOneWidget);
        expect(
          find.byKey(const Key('qr_camera_grant_button')),
          findsNothing,
        );
      },
    );

    testWidgets(
      'state: permanentlyDenied → notice and settings CTA present; tapping invokes settings opener',
      (tester) async {
        final requester = _FakePermissionRequester(
          status: PermissionStatus.permanentlyDenied,
        );
        final opener = _FakeAppSettingsOpener();
        final gate = PermissionGate(
          requester: requester,
          settingsOpener: opener,
        );

        await tester.pumpWidget(buildTestWidget(gate: gate));
        await tester.pumpAndSettle();

        // Scanner absent
        expect(find.byKey(fakeScannerKey), findsNothing);
        expect(
          find.byKey(const Key('qr_viewfinder_overlay')),
          findsNothing,
        );

        // Notice and settings CTA present
        expect(
          find.byKey(
            const Key('permission_rationale_permanently_denied_notice'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('qr_camera_open_settings_button')),
          findsOneWidget,
        );
        expect(find.text('Buka Pengaturan'), findsOneWidget);
        expect(
          find.byKey(const Key('qr_camera_grant_button')),
          findsNothing,
        );

        // Tapping CTA invokes injected opener
        await tester.tap(
          find.byKey(const Key('qr_camera_open_settings_button')),
        );
        await tester.pumpAndSettle();

        expect(opener.calls, 1);
      },
    );

    testWidgets(
      'resumed lifecycle re-check: flip requester to granted and resume shows scanner',
      (tester) async {
        final requester = _FakePermissionRequester(
          status: PermissionStatus.denied,
        );
        final opener = _FakeAppSettingsOpener();
        final gate = PermissionGate(
          requester: requester,
          settingsOpener: opener,
        );

        await tester.pumpWidget(buildTestWidget(gate: gate));
        await tester.pumpAndSettle();

        expect(find.byKey(fakeScannerKey), findsNothing);
        expect(
          find.byKey(const Key('qr_camera_grant_button')),
          findsOneWidget,
        );

        // User granted camera permission in system settings, then returns to app
        requester.status = PermissionStatus.granted;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();

        expect(find.byKey(fakeScannerKey), findsOneWidget);
        expect(
          find.byKey(const Key('qr_camera_grant_button')),
          findsNothing,
        );
        expect(
          find.byKey(const Key('qr_viewfinder_overlay')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'loading state: while permission check is pending, render neutral dark placeholder with CircularProgressIndicator',
      (tester) async {
        final checkCompleter = Completer<PermissionStatus>();
        final requester = _FakePermissionRequester(
          status: PermissionStatus.granted,
          pendingCheck: checkCompleter,
        );
        final gate = PermissionGate(requester: requester);

        await tester.pumpWidget(buildTestWidget(gate: gate));
        await tester.pump();

        // While pending, dark placeholder with spinner is displayed
        expect(
          find.byKey(const Key('qr_camera_loading_placeholder')),
          findsOneWidget,
        );
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byKey(fakeScannerKey), findsNothing);

        // Complete the check
        checkCompleter.complete(PermissionStatus.granted);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('qr_camera_loading_placeholder')),
          findsNothing,
        );
        expect(find.byKey(fakeScannerKey), findsOneWidget);
      },
    );

    testWidgets(
      'camera busy state: renders friendly message and retry CTA calls onRetry',
      (tester) async {
        var retryCalled = false;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.darkTheme,
            home: Scaffold(
              body: CameraBusyView(
                onRetry: () {
                  retryCalled = true;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('qr_camera_busy_view')),
          findsOneWidget,
        );
        expect(
          find.text('Kamera sedang dipakai aplikasi lain'),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('qr_camera_retry_button')),
          findsOneWidget,
        );
        expect(find.text('Coba Lagi'), findsOneWidget);

        await tester.tap(find.byKey(const Key('qr_camera_retry_button')));
        await tester.pumpAndSettle();

        expect(retryCalled, isTrue);
      },
    );
  });
}
