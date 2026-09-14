import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill_import_preview.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill_scan.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_state.dart';
import '../../../../helpers/mocks.dart';

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
      await Future.delayed(const Duration(milliseconds: 10));

      final loaded = cubit.state as SkillsLoaded;
      expect(loaded.allSkills.length, 3);
      expect(service.getSkill('new_skill'), isNotNull);
    });
  });

  group('SkillsCubit skill import', () {
    const importedSkill = Skill(
      id: 'imported_skill',
      name: 'imported_skill',
      description: 'Imported',
      category: 'Productivity',
      tier: 'Tier 1 Auto',
    );
    const cleanScan = SkillScanResult();
    const rejectedScan = SkillScanResult(
      findings: [
        SkillScanFinding(
          patternId: 'ignore_previous_instructions',
          description: 'x',
          severity: SkillScanSeverity.critical,
        ),
      ],
    );

    SkillImportPreview cleanPreview() {
      return const SkillImportPreview(
        sourceUrl: 'https://example.com/SKILL.md',
        skill: importedSkill,
        rawMarkdown: '---\nname: x\n---\n',
        scan: cleanScan,
      );
    }

    SkillImportPreview rejectedPreview() {
      return const SkillImportPreview(
        sourceUrl: 'https://example.com/SKILL.md',
        skill: importedSkill,
        rawMarkdown: '---\nname: x\n---\n',
        scan: rejectedScan,
      );
    }

    setUpAll(() {
      registerFallbackValue('fallback');
      registerFallbackValue(cleanPreview());
    });

    test('importSkillFromUrl publishes preview on success', () async {
      final mockImport = MockSkillImportService();
      final svc = SkillsRegistryService(loadDefaults: false);
      final c = SkillsCubit(
        skillsRegistryService: svc,
        skillImportService: mockImport,
        autoLoad: false,
      );
      await c.loadSkills();
      final preview = cleanPreview();
      when(() => mockImport.buildPreview(any()))
          .thenAnswer((_) async => Right(preview));

      await c.importSkillFromUrl('https://example.com/SKILL.md');

      final loaded = c.state as SkillsLoaded;
      expect(loaded.importPreview, preview);
      expect(loaded.importError, isNull);
      expect(loaded.importBusy, isFalse);
      await c.close();
    });

    test('importSkillFromUrl surfaces failure message', () async {
      final mockImport = MockSkillImportService();
      final svc = SkillsRegistryService(loadDefaults: false);
      final c = SkillsCubit(
        skillsRegistryService: svc,
        skillImportService: mockImport,
        autoLoad: false,
      );
      await c.loadSkills();
      when(() => mockImport.buildPreview(any()))
          .thenAnswer((_) async => const Left(NetworkFailure('boom')));

      await c.importSkillFromUrl('https://example.com/SKILL.md');

      final loaded = c.state as SkillsLoaded;
      expect(loaded.importError, 'boom');
      expect(loaded.importPreview, isNull);
      expect(loaded.importBusy, isFalse);
      await c.close();
    });

    test('confirmSkillImport rejects blocked preview', () async {
      final mockImport = MockSkillImportService();
      final svc = SkillsRegistryService(loadDefaults: false);
      final c = SkillsCubit(
        skillsRegistryService: svc,
        skillImportService: mockImport,
        autoLoad: false,
      );
      await c.loadSkills();
      final preview = rejectedPreview();
      when(() => mockImport.buildPreview(any()))
          .thenAnswer((_) async => Right(preview));

      await c.importSkillFromUrl('https://example.com/SKILL.md');
      final result = await c.confirmSkillImport();

      expect(result, isNull);
      final loaded = c.state as SkillsLoaded;
      expect(
        loaded.importError,
        preview.scan.rejectionReason,
      );
      expect(loaded.importPreview, preview);
      expect(svc.getSkill(importedSkill.id), isNull);
      verifyNever(() => mockImport.confirmImport(any()));
      await c.close();
    });

    test('confirmSkillImport registers accepted preview', () async {
      final mockImport = MockSkillImportService();
      final svc = SkillsRegistryService(loadDefaults: false);
      final c = SkillsCubit(
        skillsRegistryService: svc,
        skillImportService: mockImport,
        autoLoad: false,
      );
      await c.loadSkills();
      final preview = cleanPreview();
      when(() => mockImport.buildPreview(any()))
          .thenAnswer((_) async => Right(preview));
      when(() => mockImport.confirmImport(any())).thenAnswer((inv) async {
        final p = inv.positionalArguments.first as SkillImportPreview;
        svc.registerSkill(p.skill);
        return Right(p.skill);
      });

      await c.importSkillFromUrl('https://example.com/SKILL.md');
      final result = await c.confirmSkillImport();

      expect(result, isNotNull);
      expect(result!.id, importedSkill.id);
      expect(svc.getSkill(importedSkill.id), isNotNull);
      final loaded = c.state as SkillsLoaded;
      expect(loaded.importPreview, isNull);
      expect(loaded.importError, isNull);
      await c.close();
    });

    test('clearSkillImport clears preview and error', () async {
      final mockImport = MockSkillImportService();
      final svc = SkillsRegistryService(loadDefaults: false);
      final c = SkillsCubit(
        skillsRegistryService: svc,
        skillImportService: mockImport,
        autoLoad: false,
      );
      await c.loadSkills();
      final preview = cleanPreview();
      when(() => mockImport.buildPreview(any()))
          .thenAnswer((_) async => Right(preview));

      await c.importSkillFromUrl('https://example.com/SKILL.md');
      expect((c.state as SkillsLoaded).importPreview, isNotNull);
      c.clearSkillImport();

      final loaded = c.state as SkillsLoaded;
      expect(loaded.importPreview, isNull);
      expect(loaded.importError, isNull);
      expect(loaded.importBusy, isFalse);
      await c.close();
    });

    test('importSkillFromUrl without service sets error', () async {
      final svc = SkillsRegistryService(loadDefaults: false);
      final c = SkillsCubit(
        skillsRegistryService: svc,
        autoLoad: false,
      );
      await c.loadSkills();

      await c.importSkillFromUrl('https://example.com/SKILL.md');

      final loaded = c.state as SkillsLoaded;
      expect(loaded.importError, isNotNull);
      expect(loaded.importBusy, isFalse);
      await c.close();
    });
  });
}
