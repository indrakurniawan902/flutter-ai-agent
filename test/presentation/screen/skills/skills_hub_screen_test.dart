import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/skills_hub_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget createWidgetUnderTest() {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: const SkillsHubScreen(),
    );
  }

  group('SkillsHubScreen', () {
    testWidgets('renders app bar with title and search field', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Skills Hub'), findsOneWidget);
      expect(find.byKey(const Key('skills_search_field')), findsOneWidget);
      expect(find.byKey(const Key('skills_filter_pills')), findsOneWidget);
    });

    testWidgets('renders category filter pills and clicking filters list', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('skills_filter_pill_all')), findsOneWidget);
      expect(find.byKey(const Key('skills_filter_pill_device')), findsOneWidget);
      expect(find.byKey(const Key('skills_filter_pill_automations')), findsOneWidget);
      expect(find.byKey(const Key('skills_filter_pill_system')), findsOneWidget);
      expect(find.byKey(const Key('skills_filter_pill_vision')), findsOneWidget);

      // Default shows all skills
      expect(find.text('camera_vision'), findsOneWidget);
      expect(find.text('location_context'), findsOneWidget);

      // Tap 'Device' filter
      await tester.tap(find.byKey(const Key('skills_filter_pill_device')));
      await tester.pumpAndSettle();

      // Only device skills shown (location_context is in device, camera_vision is in vision)
      expect(find.text('location_context'), findsOneWidget);
      expect(find.text('camera_vision'), findsNothing);
    });

    testWidgets('searching text filters skill cards by name or description', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('skills_search_field')), 'camera');
      await tester.pumpAndSettle();

      expect(find.text('camera_vision'), findsOneWidget);
      expect(find.text('clipboard_manager'), findsNothing);
    });

    testWidgets('shows empty state when no skills match search', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('skills_search_field')), 'nonexistent_skill_xyz');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('skills_empty_state')), findsOneWidget);
      expect(find.text('No matching skills found'), findsOneWidget);
    });
  });
}
