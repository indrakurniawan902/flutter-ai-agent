import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ai_agent/domain/services/skills/skill_security_scanner.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';

void main() {
  group('import tier gate', () {
    late SkillsRegistryService registry;
    late SkillSecurityScanner scanner;

    setUp(() {
      registry = SkillsRegistryService(loadDefaults: false);
      scanner = SkillSecurityScanner();
    });

    void expectDisabledAfterPolicy(String tier) {
      final markdown = '---\n'
          'name: tier_probe\n'
          'description: Probe\n'
          'tier: $tier\n'
          '---\n'
          '\n'
          'Body.\n';
      final parsed = registry.parseSkillFromMarkdown(markdown);
      expect(parsed.isEnabled, isTrue, reason: 'parser default for $tier');
      final applied = scanner.applyImportPolicy(parsed);
      expect(applied.isEnabled, isFalse, reason: tier);
    }

    test('tier 1 auto still imports disabled', () {
      expectDisabledAfterPolicy('Tier 1 Auto');
    });

    test('tier 3 hitl imports disabled', () {
      expectDisabledAfterPolicy('3 HITL');
    });

    test('unicode roman numeral tier imports disabled', () {
      expectDisabledAfterPolicy('Ⅲ');
    });
  });
}
