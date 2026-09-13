import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/security_policy.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';

void main() {
  late SkillsRegistryService service;

  setUp(() {
    service = SkillsRegistryService(loadDefaults: false);
  });

  group('SkillsRegistryService - Parsing YAML/Markdown', () {
    test('parses full YAML frontmatter and Markdown body correctly', () {
      const markdown = '''---
name: camera_vision
description: Camera image perception and visual reasoning via vision models
category: Device Control
tier: Tier 2 Perm
version: 1.2.0
author: Flames
tools:
  - take_photo
  - analyze_image
prompts:
  - "Take a photo of this document and transcribe text"
  - "What is in front of the camera?"
is_community: false
is_enabled: true
---

# Camera Vision Skill
Use this skill when the user asks to inspect the physical environment or analyze camera input.
''';

      final skill = service.parseSkillFromMarkdown(markdown);

      expect(skill.id, 'camera_vision');
      expect(skill.name, 'camera_vision');
      expect(
        skill.description,
        'Camera image perception and visual reasoning via vision models',
      );
      expect(skill.category, 'Device Control');
      expect(skill.tier, 'Tier 2 Perm');
      expect(skill.version, '1.2.0');
      expect(skill.author, 'Flames');
      expect(skill.tools, ['take_photo', 'analyze_image']);
      expect(skill.prompts, [
        'Take a photo of this document and transcribe text',
        'What is in front of the camera?',
      ]);
      expect(skill.isCommunity, isFalse);
      expect(skill.isEnabled, isTrue);
      expect(
        skill.instructions.trim(),
        '# Camera Vision Skill\nUse this skill when the user asks to inspect the physical environment or analyze camera input.',
      );
    });

    test('parses minimal YAML frontmatter and assigns robust defaults', () {
      const minimalMarkdown = '''---
name: minimal_skill
description: Minimal test skill
---

Minimal body content.
''';

      final skill = service.parseSkillFromMarkdown(minimalMarkdown);

      expect(skill.id, 'minimal_skill');
      expect(skill.name, 'minimal_skill');
      expect(skill.description, 'Minimal test skill');
      expect(skill.category, 'Productivity');
      expect(skill.tier, 'Tier 1 Auto');
      expect(skill.version, '1.0.0');
      expect(skill.tools, isEmpty);
      expect(skill.prompts, isEmpty);
      expect(skill.isEnabled, isTrue);
      expect(skill.instructions.trim(), 'Minimal body content.');
    });

    test('handles markdown without YAML frontmatter gracefully', () {
      const rawMarkdown = '''# Raw Skill
This is a raw skill without frontmatter headers.
''';

      final skill = service.parseSkillFromMarkdown(rawMarkdown);

      expect(skill.id, isNotEmpty);
      expect(skill.name, isNotEmpty);
      expect(skill.instructions, contains('This is a raw skill'));
    });

    test(
        'handles YAML frontmatter containing dashes and special characters in description',
        () {
      const complexMarkdown = '''---
name: complex_parser_skill
description: "Handles dashes -- and em-dashes --- inside strings"
category: Productivity
tools:
  - clipboard_read
---

Body text with a horizontal rule below:

---

And more instructions.
''';

      final skill = service.parseSkillFromMarkdown(complexMarkdown);

      expect(skill.id, 'complex_parser_skill');
      expect(skill.description,
          'Handles dashes -- and em-dashes --- inside strings');
      expect(skill.instructions,
          contains('Body text with a horizontal rule below:'));
      expect(skill.instructions, contains('And more instructions.'));
    });
  });

  group('SkillsRegistryService - Registration & Toggle', () {
    test('registers a skill and retrieves by id or name', () {
      const skill = Skill(
        id: 'test_calc',
        name: 'test_calc',
        description: 'Calculator skill',
        category: 'Finance',
        tier: 'Tier 1 Auto',
        version: '1.0.0',
        tools: ['calc'],
        prompts: ['Calculate 2 + 2'],
        instructions: 'Perform calculation operations.',
      );

      service.registerSkill(skill);

      expect(service.getAllSkills().length, 1);
      expect(service.getSkill('test_calc'), equals(skill));
    });

    test('registers skill directly from markdown definition', () {
      const markdown = '''---
name: task_planner
description: Plan project tasks
category: Productivity
---
Break tasks down into chunks.
''';

      final registered = service.registerSkillFromMarkdown(markdown);

      expect(registered.id, 'task_planner');
      expect(service.getSkill('task_planner'), isNotNull);
    });

    test('toggles skill enabled and disabled state', () {
      const skill = Skill(
        id: 'toggle_test',
        name: 'toggle_test',
        description: 'Toggle skill',
        category: 'Automation',
        tier: 'Tier 1 Auto',
        version: '1.0.0',
        isEnabled: true,
      );

      service.registerSkill(skill);
      expect(service.isSkillEnabled('toggle_test'), isTrue);
      expect(service.getActiveSkills().length, 1);

      service.setSkillEnabled('toggle_test', false);
      expect(service.isSkillEnabled('toggle_test'), isFalse);
      expect(service.getActiveSkills(), isEmpty);

      service.setSkillEnabled('toggle_test', true);
      expect(service.isSkillEnabled('toggle_test'), isTrue);
      expect(service.getActiveSkills().length, 1);
    });

    test('unregisters a skill', () {
      const skill = Skill(
        id: 'to_remove',
        name: 'to_remove',
        description: 'Skill to remove',
        category: 'Productivity',
        tier: 'Tier 1 Auto',
        version: '1.0.0',
      );

      service.registerSkill(skill);
      expect(service.getSkill('to_remove'), isNotNull);

      service.unregisterSkill('to_remove');
      expect(service.getSkill('to_remove'), isNull);
    });
  });

  group('SkillsRegistryService - Category Filter & Search', () {
    setUp(() {
      service.registerSkill(const Skill(
        id: 's_prod',
        name: 'task_planner',
        description: 'Organize daily workflows and tasks',
        category: 'Productivity',
        tier: 'Tier 1 Auto',
        version: '1.0.0',
        tools: ['clipboard_write'],
      ));
      service.registerSkill(const Skill(
        id: 's_fin',
        name: 'expense_calculator',
        description: 'Track expenses and convert currency',
        category: 'Finance',
        tier: 'Tier 1 Auto',
        version: '1.0.0',
      ));
      service.registerSkill(const Skill(
        id: 's_dev',
        name: 'camera_vision',
        description: 'Visual reasoning and scene analysis',
        category: 'Device Control',
        tier: 'Tier 2 Perm',
        version: '1.0.0',
        tools: ['take_photo'],
      ));
      service.registerSkill(const Skill(
        id: 's_auto',
        name: 'calendar_scheduler',
        description: 'Automate calendar entries and invites',
        category: 'Automation',
        tier: 'Tier 3 HITL',
        version: '1.0.0',
      ));
    });

    test('filters skills by category matching case-insensitively', () {
      final prod = service.getSkillsByCategory('Productivity');
      expect(prod.length, 1);
      expect(prod.first.name, 'task_planner');

      final fin = service.getSkillsByCategory('Finance');
      expect(fin.length, 1);
      expect(fin.first.name, 'expense_calculator');

      final dev = service.getSkillsByCategory('Device Control');
      expect(dev.length, 1);
      expect(dev.first.name, 'camera_vision');

      final all = service.getSkillsByCategory('All');
      expect(all.length, 4);
    });

    test('searches skills across name, description, and tools', () {
      final res1 = service.searchSkills('expense');
      expect(res1.length, 1);
      expect(res1.first.name, 'expense_calculator');

      final res2 = service.searchSkills('clipboard_write');
      expect(res2.length, 1);
      expect(res2.first.name, 'task_planner');

      final res3 = service.searchSkills('nonexistent');
      expect(res3, isEmpty);
    });
  });

  group('SkillsRegistryService - System Prompt Injection', () {
    test('builds system prompt containing active skills and excludes disabled ones',
        () {
      service.registerSkill(const Skill(
        id: 'active_skill',
        name: 'active_skill',
        description: 'Active helper',
        category: 'Productivity',
        tier: 'Tier 1 Auto',
        version: '1.0.0',
        tools: ['tool_a'],
        prompts: ['Prompt 1'],
        instructions: 'Active instructions here.',
        isEnabled: true,
      ));

      service.registerSkill(const Skill(
        id: 'disabled_skill',
        name: 'disabled_skill',
        description: 'Disabled helper',
        category: 'Finance',
        tier: 'Tier 1 Auto',
        version: '1.0.0',
        tools: ['tool_b'],
        instructions: 'Should not appear.',
        isEnabled: false,
      ));

      final prompt = service.buildSystemPrompt();

      expect(prompt, contains('active_skill'));
      expect(prompt, contains('Active instructions here.'));
      expect(prompt, contains('tool_a'));
      expect(prompt, contains('Prompt 1'));
      expect(prompt, isNot(contains('disabled_skill')));
      expect(prompt, isNot(contains('Should not appear.')));
    });

    test('returns empty or base prompt when no skills are active', () {
      final prompt = service.buildSystemPrompt(basePrompt: 'Base prompt.');
      expect(prompt, 'Base prompt.');
    });
  });

  group('SkillsRegistryService - ToolRegistry Sync', () {
    late ToolRegistry toolRegistry;

    setUp(() {
      toolRegistry = ToolRegistry();
      toolRegistry.register(RegisteredTool(
        name: 'tool_photo',
        description: 'Take photo',
        parameters: const {'type': 'object'},
        securityTier: SecurityTier.tier1Auto,
        execute: (_) async => const Right('photo_taken'),
      ));
      toolRegistry.register(RegisteredTool(
        name: 'tool_shared',
        description: 'Shared tool',
        parameters: const {'type': 'object'},
        securityTier: SecurityTier.tier1Auto,
        execute: (_) async => const Right('shared_done'),
      ));
    });

    test(
        'syncWithToolRegistry enables active skill tools and disables inactive skill tools',
        () {
      const skillA = Skill(
        id: 'skill_a',
        name: 'skill_a',
        description: 'Skill A',
        category: 'Device Control',
        tier: 'Tier 1 Auto',
        version: '1.0.0',
        tools: ['tool_photo'],
        isEnabled: false,
      );
      const skillB = Skill(
        id: 'skill_b',
        name: 'skill_b',
        description: 'Skill B',
        category: 'Productivity',
        tier: 'Tier 1 Auto',
        version: '1.0.0',
        tools: ['tool_shared'],
        isEnabled: true,
      );

      service.registerSkill(skillA);
      service.registerSkill(skillB);

      service.syncWithToolRegistry(toolRegistry);

      expect(toolRegistry.isToolEnabled('tool_photo'), isFalse);
      expect(toolRegistry.isToolEnabled('tool_shared'), isTrue);

      final openAiDefs = toolRegistry.getOpenAiToolDefinitions();
      expect(openAiDefs.any((t) => t['function']['name'] == 'tool_photo'),
          isFalse);
      expect(openAiDefs.any((t) => t['function']['name'] == 'tool_shared'),
          isTrue);
    });
  });

  group('SkillsRegistryService - Bundled Skills', () {
    test('includes the doc_builder skill with its export tool', () {
      final bundled = SkillsRegistryService();

      final ids = bundled.getAllSkills().map((s) => s.id).toList();
      expect(ids, contains('doc_builder'));

      final skill = bundled.getSkill('doc_builder');
      expect(skill, isNotNull);
      expect(skill!.isEnabled, isTrue);
      expect(skill.tools, contains('export_document_pdf'));
    });
  });
}
