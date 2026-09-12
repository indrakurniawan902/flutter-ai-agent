import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/skill_detail_sheet.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/skills_hub_screen.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

void main() {
  late SkillsRegistryService testRegistryService;
  late SkillsCubit testCubit;

  setUp(() {
    testRegistryService = SkillsRegistryService(loadDefaults: false);
    testRegistryService.registerSkill(const Skill(
      id: 'task_planner',
      name: 'task_planner',
      description: 'Decomposes complex goals into sequential steps',
      category: 'Productivity',
      tier: 'Tier 1 Auto',
      version: 'v1.2.0',
      tools: ['clipboard_read', 'clipboard_write'],
      prompts: ['Plan out steps to organize a conference'],
      instructions: 'Break down goals into milestones.',
      isEnabled: true,
    ));
    testRegistryService.registerSkill(const Skill(
      id: 'expense_calculator',
      name: 'expense_calculator',
      description: 'Calculate currency conversions and split bills',
      category: 'Finance',
      tier: 'Tier 1 Auto',
      version: 'v1.0.3',
      tools: ['clipboard_read'],
      prompts: ['Calculate split bill and 15% tip for 4 people'],
      isEnabled: true,
    ));
    testRegistryService.registerSkill(const Skill(
      id: 'camera_vision',
      name: 'camera_vision',
      description: 'Camera perception and visual reasoning',
      category: 'Device Control',
      tier: 'Tier 2 Perm',
      version: 'v1.2.0',
      tools: ['take_photo', 'analyze_image'],
      prompts: ['Take a photo of this document'],
      isEnabled: true,
    ));
    testRegistryService.registerSkill(const Skill(
      id: 'calendar_scheduler',
      name: 'calendar_scheduler',
      description: 'Calendar event inspection and scheduling',
      category: 'Automation',
      tier: 'Tier 3 HITL',
      version: 'v1.0.1',
      tools: ['get_calendar_events', 'create_calendar_event'],
      prompts: ['Schedule meeting tomorrow at 10 AM'],
      isEnabled: true,
    ));

    testCubit = SkillsCubit(
      skillsRegistryService: testRegistryService,
      autoLoad: true,
    );
  });

  tearDown(() {
    testCubit.close();
  });

  Widget createWidgetUnderTest({SkillsCubit? cubit}) {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: SkillsHubScreen(cubit: cubit ?? testCubit),
    );
  }

  group('SkillsHubScreen - Category Filters & Cards', () {
    testWidgets(
        'renders app bar, active count, search bar, and filter pills',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Skills Hub'), findsOneWidget);
      expect(find.byKey(const Key('skills_search_field')), findsOneWidget);
      expect(find.byKey(const Key('skills_filter_pills')), findsOneWidget);

      expect(find.byKey(const Key('skills_filter_pill_all')), findsOneWidget);
      expect(find.byKey(const Key('skills_filter_pill_productivity')),
          findsOneWidget);
      expect(find.byKey(const Key('skills_filter_pill_finance')),
          findsOneWidget);
      expect(find.byKey(const Key('skills_filter_pill_device')),
          findsOneWidget);
      expect(find.byKey(const Key('skills_filter_pill_automations')),
          findsOneWidget);

      expect(find.text('4 Active'), findsOneWidget);
    });

    testWidgets('clicking category pills filters displayed skill cards',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('task_planner'), findsOneWidget);
      expect(find.text('expense_calculator'), findsOneWidget);
      expect(find.text('camera_vision'), findsOneWidget);

      await tester.tap(find.byKey(const Key('skills_filter_pill_productivity')));
      await tester.pumpAndSettle();

      expect(find.text('task_planner'), findsOneWidget);
      expect(find.text('expense_calculator'), findsNothing);
      expect(find.text('camera_vision'), findsNothing);

      await tester.tap(find.byKey(const Key('skills_filter_pill_finance')));
      await tester.pumpAndSettle();

      expect(find.text('expense_calculator'), findsOneWidget);
      expect(find.text('task_planner'), findsNothing);

      await tester.tap(find.byKey(const Key('skills_filter_pill_automations')));
      await tester.pumpAndSettle();

      expect(find.text('calendar_scheduler'), findsOneWidget);
      expect(find.text('expense_calculator'), findsNothing);
    });

    testWidgets('toggling skill switch updates state and active count',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('4 Active'), findsOneWidget);

      final toggleFinder = find.byKey(const Key('skill_toggle_task_planner'));
      expect(toggleFinder, findsOneWidget);

      await tester.tap(toggleFinder);
      await tester.pumpAndSettle();

      expect(find.text('3 Active'), findsOneWidget);
      expect(testRegistryService.isSkillEnabled('task_planner'), isFalse);
    });
  });

  group('SkillsHubScreen - Search & Empty State', () {
    testWidgets('searching text filters skill cards by name or description',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('skills_search_field')), 'camera');
      await tester.pumpAndSettle();

      expect(find.text('camera_vision'), findsOneWidget);
      expect(find.text('task_planner'), findsNothing);
    });

    testWidgets('shows empty state when no skills match search',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('skills_search_field')),
          'nonexistent_skill_xyz');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('skills_empty_state')), findsOneWidget);
      expect(find.text('No matching skills found'), findsOneWidget);
    });
  });

  group('SkillsHubScreen - Skill Detail Modal', () {
    testWidgets(
        'tapping skill card opens modal showing tool requirements and sample prompts',
        (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('skill_card_task_planner')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('skill_detail_sheet')), findsOneWidget);
      expect(find.text('Tool Requirements'), findsOneWidget);
      expect(find.text('Sample Prompts'), findsOneWidget);

      expect(find.text('clipboard_read'), findsOneWidget);
      expect(find.text('clipboard_write'), findsOneWidget);

      expect(find.textContaining('Plan out steps to organize a conference'),
          findsOneWidget);

      final modalToggle = find.byKey(const Key('skill_detail_toggle'));
      expect(modalToggle, findsOneWidget);
      await tester.tap(modalToggle);
      await tester.pumpAndSettle();
      expect(testRegistryService.isSkillEnabled('task_planner'), isFalse);

      await tester.tap(find.byKey(const Key('skill_detail_close_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('skill_detail_sheet')), findsNothing);
    });

    testWidgets(
        'skill detail modal does not overflow on narrow mobile screens (320x568)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const testSkill = Skill(
        id: 'camera_vision',
        name: 'camera_vision',
        description: 'Camera perception and visual reasoning',
        category: 'Device Control',
        tier: 'Tier 2 Perm',
        version: 'v1.2.0',
        tools: ['take_photo', 'analyze_image'],
        prompts: ['Take a photo of this document'],
        isEnabled: true,
      );

      await tester.pumpWidget(MaterialApp(
        theme: HermesTheme.darkTheme,
        home: const Scaffold(
          body: SkillDetailSheet(
            skill: testSkill,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('skill_detail_sheet')), findsOneWidget);
      expect(find.text('Tier 2 Perm'), findsOneWidget);
      expect(find.text('DEVICE CONTROL'), findsOneWidget);
    });
  });
}
