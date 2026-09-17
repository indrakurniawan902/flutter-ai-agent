import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/domain/tools/chat/overlay_bubble_service.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/widgets/overlay_bubble_settings_tile.dart';
import 'package:flutter_ai_agent/presentation/widget/app_toast.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockOverlayBubbleService extends Mock
    implements OverlayBubbleServiceBase {}

void main() {
  late MockOverlayBubbleService mock;

  setUp(() {
    mock = MockOverlayBubbleService();
  });

  tearDown(AppToast.dismissAll);

  Widget buildTile() {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: OverlayBubbleSettingsTile(service: mock),
      ),
    );
  }

  SwitchListTile tile(WidgetTester tester) {
    return tester.widget<SwitchListTile>(
      find.byKey(const Key('settings_overlay_bubble_toggle')),
    );
  }

  testWidgets(
    'granted + persisted OFF renders OFF without touching the bubble',
    (tester) async {
      when(() => mock.isBubbleEnabled()).thenAnswer((_) async => false);
      when(() => mock.checkPermission())
          .thenAnswer((_) async => OverlayPermissionState.granted);

      await tester.pumpWidget(buildTile());
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(const Key('settings_overlay_bubble_toggle')),
        findsOneWidget,
      );
      expect(tile(tester).value, isFalse);
      verify(() => mock.isBubbleEnabled()).called(1);
      verify(() => mock.checkPermission()).called(1);
      verifyNever(() => mock.setBubbleEnabled(any()));
    },
  );

  testWidgets('granted tap enables the bubble and flips the switch ON',
      (tester) async {
    when(() => mock.isBubbleEnabled()).thenAnswer((_) async => false);
    when(() => mock.checkPermission())
        .thenAnswer((_) async => OverlayPermissionState.granted);
    when(() => mock.setBubbleEnabled(true)).thenAnswer((_) async => true);

    await tester.pumpWidget(buildTile());
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('settings_overlay_bubble_toggle')),
    );
    await tester.pumpAndSettle();

    expect(tile(tester).value, isTrue);
    verify(() => mock.setBubbleEnabled(true)).called(1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('denied tap shows the rationale modal and never creates bubble',
      (tester) async {
    when(() => mock.isBubbleEnabled()).thenAnswer((_) async => false);
    when(() => mock.checkPermission())
        .thenAnswer((_) async => OverlayPermissionState.denied);

    await tester.pumpWidget(buildTile());
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('settings_overlay_bubble_toggle')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('permission_rationale_title')),
      findsOneWidget,
    );
    expect(find.text('Floating Bubble'), findsWidgets);
    verifyNever(() => mock.setBubbleEnabled(any()));
    expect(tile(tester).value, isFalse);
  });

  testWidgets(
    'permanently denied tap shows the Open App Settings CTA',
    (tester) async {
      when(() => mock.isBubbleEnabled()).thenAnswer((_) async => false);
      when(() => mock.checkPermission())
          .thenAnswer((_) async => OverlayPermissionState.permanentlyDenied);

      await tester.pumpWidget(buildTile());
      await tester.pump();
      await tester.pump();

      await tester.tap(
        find.byKey(const Key('settings_overlay_bubble_toggle')),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('permission_rationale_title')),
        findsOneWidget,
      );
      expect(find.text('Buka Pengaturan'), findsOneWidget);
      verifyNever(() => mock.setBubbleEnabled(any()));
      expect(tile(tester).value, isFalse);
    },
  );

  testWidgets('failed enable keeps the switch OFF and surfaces no exception',
      (tester) async {
    when(() => mock.isBubbleEnabled()).thenAnswer((_) async => false);
    when(() => mock.checkPermission())
        .thenAnswer((_) async => OverlayPermissionState.granted);
    when(() => mock.setBubbleEnabled(true)).thenAnswer((_) async => false);

    await tester.pumpWidget(buildTile());
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.byKey(const Key('settings_overlay_bubble_toggle')),
    );
    await tester.pumpAndSettle();

    expect(tile(tester).value, isFalse);
    expect(tester.takeException(), isNull);

    AppToast.dismissAll();
    await tester.pump();
  });

  testWidgets('subtitle names both tap and hold behaviours', (tester) async {
    when(() => mock.isBubbleEnabled()).thenAnswer((_) async => false);
    when(() => mock.checkPermission())
        .thenAnswer((_) async => OverlayPermissionState.granted);

    await tester.pumpWidget(buildTile());
    await tester.pump();
    await tester.pump();

    expect(
      find.text('Floating bubble shown over other apps. '
          'Tap to open Flames, hold to talk.'),
      findsOneWidget,
    );
    expect(find.textContaining('tap-to-talk'), findsNothing);
  });

  testWidgets('subtitle is non-blank ASCII with no emoji', (tester) async {
    when(() => mock.isBubbleEnabled()).thenAnswer((_) async => false);
    when(() => mock.checkPermission())
        .thenAnswer((_) async => OverlayPermissionState.granted);

    await tester.pumpWidget(buildTile());
    await tester.pump();
    await tester.pump();

    final subtitle = tester.widget<Text>(
      find.text('Floating bubble shown over other apps. '
          'Tap to open Flames, hold to talk.'),
    );
    final text = subtitle.data!;
    expect(text.trim(), isNotEmpty);
    expect(RegExp(r'^[\x00-\x7F]+$').hasMatch(text), isTrue);
  });

  testWidgets('persisted ON renders ON after the initial load',
      (tester) async {
    when(() => mock.isBubbleEnabled()).thenAnswer((_) async => true);
    when(() => mock.checkPermission())
        .thenAnswer((_) async => OverlayPermissionState.granted);

    await tester.pumpWidget(buildTile());
    await tester.pump();
    await tester.pump();

    expect(tile(tester).value, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('throwing isBubbleEnabled renders OFF without exception',
      (tester) async {
    when(() => mock.isBubbleEnabled())
        .thenThrow(Exception('storage unavailable'));

    await tester.pumpWidget(buildTile());
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const Key('settings_overlay_bubble_toggle')),
      findsOneWidget,
    );
    expect(tile(tester).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switch-off calls setBubbleEnabled(false) and flips OFF',
      (tester) async {
    when(() => mock.isBubbleEnabled()).thenAnswer((_) async => true);
    when(() => mock.checkPermission())
        .thenAnswer((_) async => OverlayPermissionState.granted);
    when(() => mock.setBubbleEnabled(false)).thenAnswer((_) async => true);

    await tester.pumpWidget(buildTile());
    await tester.pump();
    await tester.pump();

    expect(tile(tester).value, isTrue);

    await tester.tap(
      find.byKey(const Key('settings_overlay_bubble_toggle')),
    );
    await tester.pumpAndSettle();

    expect(tile(tester).value, isFalse);
    verify(() => mock.setBubbleEnabled(false)).called(1);
    expect(tester.takeException(), isNull);
  });
}
