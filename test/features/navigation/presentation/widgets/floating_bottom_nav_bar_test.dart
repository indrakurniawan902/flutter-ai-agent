import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/features/navigation/presentation/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget createWidgetUnderTest({
    int currentIndex = 0,
    ValueChanged<int>? onTap,
  }) {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: Scaffold(
        body: const Center(child: Text('Content')),
        bottomNavigationBar: FloatingBottomNavBar(
          currentIndex: currentIndex,
          onTap: onTap ?? (_) {},
        ),
      ),
    );
  }

  group('FloatingBottomNavBar', () {
    testWidgets('renders all 5 navigation items with correct keys and labels', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('floating_bottom_nav_bar')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_chat')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_skills')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_node')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_vault')), findsOneWidget);
      expect(find.byKey(const Key('nav_item_settings')), findsOneWidget);

      expect(find.text('Chat'), findsOneWidget);
      expect(find.text('Skills'), findsOneWidget);
      expect(find.text('Node'), findsOneWidget);
      expect(find.text('Vault'), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('renders correct Material Icons and zero emojis', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.terminal), findsOneWidget);
      expect(find.byIcon(Icons.extension_outlined), findsOneWidget);
      expect(find.byIcon(Icons.router_outlined), findsOneWidget);
      expect(find.byIcon(Icons.storage_outlined), findsOneWidget);
      expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
    });

    testWidgets('active tab displays active indicator and electric teal styling', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(currentIndex: 2));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nav_indicator_node')), findsOneWidget);
      expect(find.byKey(const Key('nav_indicator_chat')), findsNothing);
    });

    testWidgets('tapping an item triggers onTap callback with index', (tester) async {
      int tappedIndex = -1;
      await tester.pumpWidget(createWidgetUnderTest(
        currentIndex: 0,
        onTap: (index) => tappedIndex = index,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_item_skills')));
      await tester.pumpAndSettle();
      expect(tappedIndex, 1);

      await tester.tap(find.byKey(const Key('nav_item_vault')));
      await tester.pumpAndSettle();
      expect(tappedIndex, 3);

      await tester.tap(find.byKey(const Key('nav_item_settings')));
      await tester.pumpAndSettle();
      expect(tappedIndex, 4);

      await tester.tap(find.byKey(const Key('nav_item_chat')));
      await tester.pumpAndSettle();
      expect(tappedIndex, 0);
    });

    testWidgets('features glassmorphism with ClipRRect and BackdropFilter', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byType(BackdropFilter), findsWidgets);
      expect(find.byType(ClipRRect), findsWidgets);
    });

    testWidgets('tapping item invokes HapticFeedback.selectionClick', (tester) async {
      final log = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (methodCall) async {
        if (methodCall.method == 'HapticFeedback.vibrate') {
          log.add(methodCall.arguments as String? ?? 'vibrate');
        }
        return null;
      });

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('nav_item_skills')));
      await tester.pumpAndSettle();

      expect(log.contains('HapticFeedbackType.selectionClick'), isTrue);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
  });
}
