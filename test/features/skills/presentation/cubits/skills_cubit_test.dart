import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_state.dart';

void main() {
  late SkillsRegistryService service;
  late SkillsCubit cubit;

  setUp(() {
    service = SkillsRegistryService(loadDefaults: false);
    service.registerSkill(const Skill(
      id: 'task_planner',
      name: 'task_planner',
      description: 'Planner',
      category: 'Productivity',
      tier: 'Tier 1 Auto',
      tools: ['clipboard_write'],
      prompts: ['Plan tasks'],
    ));
    service.registerSkill(const Skill(
      id: 'expense_calculator',
      name: 'expense_calculator',
      description: 'Expenses',
      category: 'Finance',
      tier: 'Tier 1 Auto',
    ));
    cubit = SkillsCubit(skillsRegistryService: service, autoLoad: false);
  });

  tearDown(() {
    cubit.close();
  });

  group('SkillsCubit', () {
    test('initial state is SkillsInitial', () {
      expect(cubit.state, isA<SkillsInitial>());
    });

    test('loadSkills emits SkillsLoaded with all skills and correct activeCount',
        () async {
      await cubit.loadSkills();

      expect(cubit.state, isA<SkillsLoaded>());
      final loaded = cubit.state as SkillsLoaded;
      expect(loaded.allSkills.length, 2);
      expect(loaded.filteredSkills.length, 2);
      expect(loaded.activeCount, 2);
      expect(loaded.selectedCategory, 'all');
    });

    test('selectCategory filters skills appropriately', () async {
      await cubit.loadSkills();
      cubit.selectCategory('Productivity');

      final loaded = cubit.state as SkillsLoaded;
      expect(loaded.selectedCategory, 'productivity');
      expect(loaded.filteredSkills.length, 1);
      expect(loaded.filteredSkills.first.id, 'task_planner');
    });

    test('search filters skills by query', () async {
      await cubit.loadSkills();
      cubit.search('expense');

      final loaded = cubit.state as SkillsLoaded;
      expect(loaded.searchQuery, 'expense');
      expect(loaded.filteredSkills.length, 1);
      expect(loaded.filteredSkills.first.id, 'expense_calculator');
    });

    test('toggleSkill enables and disables skill and updates activeCount',
        () async {
      await cubit.loadSkills();
      expect((cubit.state as SkillsLoaded).activeCount, 2);

      cubit.toggleSkill('task_planner', false);

      final stateAfterDisable = cubit.state as SkillsLoaded;
      expect(stateAfterDisable.activeCount, 1);
      expect(service.isSkillEnabled('task_planner'), isFalse);

      cubit.toggleSkill('task_planner', true);
      final stateAfterEnable = cubit.state as SkillsLoaded;
      expect(stateAfterEnable.activeCount, 2);
      expect(service.isSkillEnabled('task_planner'), isTrue);
    });

    test('registerSkillFromMarkdown adds new skill and reloads list', () async {
      await cubit.loadSkills();
      const markdown = '''---
name: new_skill
description: Brand new skill
category: Automation
---
Instructions.
''';

      cubit.registerSkillFromMarkdown(markdown);

      final loaded = cubit.state as SkillsLoaded;
      expect(loaded.allSkills.length, 3);
      expect(service.getSkill('new_skill'), isNotNull);
    });
  });
}
