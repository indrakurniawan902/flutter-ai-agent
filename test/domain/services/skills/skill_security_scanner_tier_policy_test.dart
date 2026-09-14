import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/services/skills/skill_security_scanner.dart';

Skill _skill({
  String id = 'skill_id',
  String name = 'notes_helper',
  String description = 'Organize notes quickly.',
  String category = 'Productivity',
  String tier = 'Tier 1 Auto',
  String version = '1.2.3',
  String author = 'Community Author',
  List<String> tools = const ['clipboard_read'],
  List<String> prompts = const ['Summarize my notes'],
  String instructions = 'Help organize notes into tidy lists.',
  bool isEnabled = true,
  bool isCommunity = false,
}) {
  return Skill(
    id: id,
    name: name,
    description: description,
    category: category,
    tier: tier,
    version: version,
    author: author,
    tools: tools,
    prompts: prompts,
    instructions: instructions,
    isEnabled: isEnabled,
    isCommunity: isCommunity,
  );
}

void main() {
  late SkillSecurityScanner scanner;

  setUp(() {
    scanner = SkillSecurityScanner();
  });

  const disabledTiers = [
    'Tier III',
    'tier three',
    'T3',
    't3',
    't-3',
    '3. HITL',
    'Tier3 HITL',
    'tier-3',
    'Tier 3 (HITL)',
    '3hitl',
    'banana',
    '',
    'four',
    'IV',
  ];

  const enabledTiers = [
    'Tier 1 Auto',
    'Tier 2',
    '1',
    '2',
    'tier 1',
    'Tier 2 (Permission)',
  ];

  test('unknown or Tier 3 spellings fail closed', () {
    for (final tier in disabledTiers) {
      final applied = scanner.applyImportPolicy(_skill(tier: tier));
      expect(applied.isEnabled, isFalse, reason: 'tier: $tier');
    }
  });

  test('known Tier 1 and Tier 2 spellings stay enabled', () {
    for (final tier in enabledTiers) {
      final applied = scanner.applyImportPolicy(_skill(tier: tier));
      expect(applied.isEnabled, isTrue, reason: 'tier: $tier');
    }
  });

  test('non-ASCII digit tiers fail closed', () {
    for (final tier in ['Tier ٣', '٣', 'Tier ３', '３']) {
      final applied = scanner.applyImportPolicy(_skill(tier: tier));
      expect(applied.isEnabled, isFalse, reason: 'tier: $tier');
    }
  });

  test('non-ASCII roman numeral tiers fail closed', () {
    for (final tier in ['Tier Ⅲ', 'Ⅲ']) {
      final applied = scanner.applyImportPolicy(_skill(tier: tier));
      expect(applied.isEnabled, isFalse, reason: 'tier: $tier');
    }
  });

  test('import always marks the skill as community', () {
    final applied = scanner.applyImportPolicy(
      _skill(tier: 'Tier 1 Auto', isCommunity: false),
    );
    expect(applied.isCommunity, isTrue);
  });

  test('an already disabled skill stays disabled', () {
    final applied = scanner.applyImportPolicy(
      _skill(tier: 'Tier 1 Auto', isEnabled: false),
    );
    expect(applied.isEnabled, isFalse);
    expect(applied.isCommunity, isTrue);
  });

  test('every other field survives the transform unchanged', () {
    final skill = _skill(tier: 'Tier 2 (Permission)');
    final applied = scanner.applyImportPolicy(skill);
    expect(applied.id, skill.id);
    expect(applied.name, skill.name);
    expect(applied.description, skill.description);
    expect(applied.category, skill.category);
    expect(applied.tier, skill.tier);
    expect(applied.version, skill.version);
    expect(applied.author, skill.author);
    expect(applied.tools, skill.tools);
    expect(applied.prompts, skill.prompts);
    expect(applied.instructions, skill.instructions);
  });

  test('Tier 3 transform preserves all other fields too', () {
    final skill = _skill(tier: 'Tier 3 HITL');
    final applied = scanner.applyImportPolicy(skill);
    expect(applied.id, skill.id);
    expect(applied.name, skill.name);
    expect(applied.description, skill.description);
    expect(applied.category, skill.category);
    expect(applied.tier, skill.tier);
    expect(applied.version, skill.version);
    expect(applied.author, skill.author);
    expect(applied.tools, skill.tools);
    expect(applied.prompts, skill.prompts);
    expect(applied.instructions, skill.instructions);
    expect(applied.isEnabled, isFalse);
    expect(applied.isCommunity, isTrue);
  });
}
