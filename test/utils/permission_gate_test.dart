import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/app_settings_opener.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/permission_rationale_modal.dart';
import 'package:flutter_ai_agent/utils/permission_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:permission_handler/permission_handler.dart';

class _MockRequester extends Mock implements PermissionRequester {}

class _FakeOpener implements AppSettingsOpener {
  int calls = 0;
  bool result = true;

  @override
  Future<bool> openAppSettings() async {
    calls++;
    return result;
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(Permission.camera);
    registerFallbackValue(Permission.location);
    registerFallbackValue(Permission.notification);
    registerFallbackValue(Permission.calendarFullAccess);
    registerFallbackValue(Permission.microphone);
    registerFallbackValue(Permission.contacts);
  });

  group('PermissionGate.permissionFor', () {
    final cases = <PermissionRationaleType, Permission>{
      PermissionRationaleType.location: Permission.location,
      PermissionRationaleType.notifications: Permission.notification,
      PermissionRationaleType.camera: Permission.camera,
      PermissionRationaleType.calendar: Permission.calendarFullAccess,
      PermissionRationaleType.microphone: Permission.microphone,
      PermissionRationaleType.contacts: Permission.contacts,
    };

    for (final entry in cases.entries) {
      test('maps ${entry.key.name} to ${entry.value}', () {
        final gate = PermissionGate(requester: _MockRequester());
        expect(gate.permissionFor(entry.key), entry.value);
      });
    }
  });

  group('PermissionGate.check & request', () {
    test('check delegates to requester with mapped permission', () async {
      final requester = _MockRequester();
      when(() => requester.checkStatus(Permission.camera))
          .thenAnswer((_) async => PermissionStatus.denied);
      final gate = PermissionGate(requester: requester);

      final status = await gate.check(PermissionRationaleType.camera);

      expect(status, PermissionStatus.denied);
      verify(() => requester.checkStatus(Permission.camera)).called(1);
    });

    test('request delegates to requester with mapped permission', () async {
      final requester = _MockRequester();
      when(() => requester.requestPermission(Permission.calendarFullAccess))
          .thenAnswer((_) async => PermissionStatus.granted);
      final gate = PermissionGate(requester: requester);

      final status = await gate.request(PermissionRationaleType.calendar);

      expect(status, PermissionStatus.granted);
      verify(() => requester.requestPermission(Permission.calendarFullAccess))
          .called(1);
    });
  });

  group('PermissionGate.requestWithRationale — 3-state flow', () {
    const allTypes = PermissionRationaleType.values;

    for (final type in allTypes) {
      testWidgets('${type.name}: granted → true, no modal shown',
          (tester) async {
        final requester = _MockRequester();
        final opener = _FakeOpener();
        when(() => requester.checkStatus(any()))
            .thenAnswer((_) async => PermissionStatus.granted);

        final gate =
            PermissionGate(requester: requester, settingsOpener: opener);
        bool? result;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('gate_trigger'),
                  onPressed: () async => result =
                      await gate.requestWithRationale(context, type),
                  child: const Text('Trigger'),
                ),
              ),
            ),
          ),
        ));

        await tester.tap(find.byKey(const Key('gate_trigger')));
        await tester.pumpAndSettle();

        expect(result, isTrue);
        expect(
          find.byKey(const Key('permission_rationale_allow_btn')),
          findsNothing,
        );
        verifyNever(() => requester.requestPermission(any()));
        expect(opener.calls, 0);
      });

      testWidgets('${type.name}: denied → modal shows allow, tap triggers request',
          (tester) async {
        final requester = _MockRequester();
        when(() => requester.checkStatus(any()))
            .thenAnswer((_) async => PermissionStatus.denied);
        when(() => requester.requestPermission(any()))
            .thenAnswer((_) async => PermissionStatus.granted);

        final gate = PermissionGate(requester: requester);
        bool? result;
        BuildContext? capturedContext;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                capturedContext = context;
                return Center(
                  child: ElevatedButton(
                    key: const Key('gate_trigger'),
                    onPressed: () async => result =
                        await gate.requestWithRationale(context, type),
                    child: const Text('Trigger'),
                  ),
                );
              },
            ),
          ),
        ));

        expect(capturedContext, isNotNull);
        await tester.tap(find.byKey(const Key('gate_trigger')));
        await tester.pumpAndSettle();

        final allowBtn =
            find.byKey(const Key('permission_rationale_allow_btn'));
        expect(allowBtn, findsOneWidget);
        expect(
          find.byKey(const Key('permission_rationale_permanently_denied_notice')),
          findsNothing,
        );
        expect(find.text('Buka Pengaturan'), findsNothing);

        await tester.tap(allowBtn);
        await tester.pumpAndSettle();

        verify(() => requester.requestPermission(any())).called(1);
        expect(result, isTrue);
      });

      testWidgets('${type.name}: denied Not Now → false, no request',
          (tester) async {
        final requester = _MockRequester();
        when(() => requester.checkStatus(any()))
            .thenAnswer((_) async => PermissionStatus.denied);

        final gate = PermissionGate(requester: requester);
        bool? result;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('gate_trigger'),
                  onPressed: () async =>
                      result = await gate.requestWithRationale(context, type),
                  child: const Text('Trigger'),
                ),
              ),
            ),
          ),
        ));

        await tester.tap(find.byKey(const Key('gate_trigger')));
        await tester.pumpAndSettle();

        await tester.tap(
          find.byKey(const Key('permission_rationale_not_now_btn')),
        );
        await tester.pumpAndSettle();

        expect(result, isFalse);
        verifyNever(() => requester.requestPermission(any()));
      });

      testWidgets(
          '${type.name}: permanentlyDenied → notice + CTA opens injected settingsOpener',
          (tester) async {
        final requester = _MockRequester();
        final opener = _FakeOpener();
        when(() => requester.checkStatus(any()))
            .thenAnswer((_) async => PermissionStatus.permanentlyDenied);

        final gate =
            PermissionGate(requester: requester, settingsOpener: opener);
        bool? result;
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  key: const Key('gate_trigger'),
                  onPressed: () async =>
                      result = await gate.requestWithRationale(context, type),
                  child: const Text('Trigger'),
                ),
              ),
            ),
          ),
        ));

        await tester.tap(find.byKey(const Key('gate_trigger')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('permission_rationale_permanently_denied_notice')),
          findsOneWidget,
        );
        expect(find.text('Buka Pengaturan'), findsOneWidget);

        await tester.tap(
          find.byKey(const Key('permission_rationale_allow_btn')),
        );
        await tester.pumpAndSettle();

        expect(opener.calls, 1);
        expect(result, isFalse);
        verifyNever(() => requester.requestPermission(any()));
      });
    }

    testWidgets('restricted also routes through permanently-denied path',
        (tester) async {
      final requester = _MockRequester();
      final opener = _FakeOpener();
      when(() => requester.checkStatus(any()))
          .thenAnswer((_) async => PermissionStatus.restricted);

      final gate = PermissionGate(requester: requester, settingsOpener: opener);
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const Key('gate_trigger'),
                onPressed: () async => result =
                    await gate.requestWithRationale(
                  context,
                  PermissionRationaleType.microphone,
                ),
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('gate_trigger')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permission_rationale_permanently_denied_notice')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const Key('permission_rationale_allow_btn')),
      );
      await tester.pumpAndSettle();

      expect(opener.calls, 1);
      expect(result, isFalse);
    });

    testWidgets('allow tap but request still returns denied → false',
        (tester) async {
      final requester = _MockRequester();
      when(() => requester.checkStatus(any()))
          .thenAnswer((_) async => PermissionStatus.denied);
      when(() => requester.requestPermission(any()))
          .thenAnswer((_) async => PermissionStatus.denied);

      final gate = PermissionGate(requester: requester);
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const Key('gate_trigger'),
                onPressed: () async => result =
                    await gate.requestWithRationale(
                  context,
                  PermissionRationaleType.location,
                ),
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('gate_trigger')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('permission_rationale_allow_btn')),
      );
      await tester.pumpAndSettle();

      verify(() => requester.requestPermission(any())).called(1);
      expect(result, isFalse);
    });

    testWidgets(
        'allow tap then request returns permanentlyDenied → no dead end, shows settings CTA',
        (tester) async {
      final requester = _MockRequester();
      final opener = _FakeOpener();
      when(() => requester.checkStatus(any()))
          .thenAnswer((_) async => PermissionStatus.denied);
      when(() => requester.requestPermission(any()))
          .thenAnswer((_) async => PermissionStatus.permanentlyDenied);

      final gate = PermissionGate(requester: requester, settingsOpener: opener);
      bool? result;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                key: const Key('gate_trigger'),
                onPressed: () async => result = await gate.requestWithRationale(
                  context,
                  PermissionRationaleType.camera,
                ),
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.byKey(const Key('gate_trigger')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const Key('permission_rationale_allow_btn')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permission_rationale_permanently_denied_notice')),
        findsOneWidget,
      );
      expect(find.text('Buka Pengaturan'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('permission_rationale_allow_btn')),
      );
      await tester.pumpAndSettle();

      expect(opener.calls, 1);
      expect(result, isFalse);
    });
  });
}
