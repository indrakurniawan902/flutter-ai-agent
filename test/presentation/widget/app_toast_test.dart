import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/presentation/widget/app_toast.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> pumpHarness(WidgetTester tester) async {
  BuildContext? captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            captured = context;
            return const Text('body');
          },
        ),
      ),
    ),
  );
  return captured!;
}

void main() {
  tearDown(AppToast.dismissAll);

  testWidgets('renders in the top-right area', (tester) async {
    final context = await pumpHarness(tester);
    AppToast.error(context, 'Connection timed out');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('app_toast')), findsOneWidget);
    expect(find.byKey(const Key('app_toast_message')), findsOneWidget);

    final topLeft = tester.getTopLeft(find.byKey(const Key('app_toast')));
    final topRight = tester.getTopRight(find.byKey(const Key('app_toast')));
    final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
    expect(topLeft.dy, lessThan(screen.height / 2));
    expect(screen.width - topRight.dx, lessThanOrEqualTo(16.0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-dismisses without exception', (tester) async {
    final context = await pumpHarness(tester);
    AppToast.error(context, 'Connection timed out');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('app_toast')), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app_toast')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at 320x568 with long message', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;

    final context = await pumpHarness(tester);
    AppToast.error(context, 'Long message ' * 20);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('app_toast')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('action button fires callback and dismisses', (tester) async {
    final context = await pumpHarness(tester);
    var tapped = false;
    AppToast.error(
      context,
      'Mic blocked',
      actionLabel: 'Open Settings',
      onAction: () => tapped = true,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const Key('app_toast_action')), findsOneWidget);
    await tester.tap(find.byKey(const Key('app_toast_action')));
    await tester.pumpAndSettle();

    expect(tapped, isTrue);
    expect(find.byKey(const Key('app_toast')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping card dismisses; dismissAll removes', (tester) async {
    var context = await pumpHarness(tester);
    AppToast.info(context, 'Hello info');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('app_toast')), findsOneWidget);

    await tester.tap(find.byKey(const Key('app_toast')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app_toast')), findsNothing);

    context = await pumpHarness(tester);
    AppToast.success(context, 'Done');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('app_toast')), findsOneWidget);

    AppToast.dismissAll();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app_toast')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
