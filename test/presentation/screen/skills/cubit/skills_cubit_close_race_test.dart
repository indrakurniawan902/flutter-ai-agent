import 'dart:async';

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

class MockSkillsRegistryService extends Mock
    implements SkillsRegistryService {}

void main() {
  const skill = Skill(
    id: 'task_planner',
    name: 'task_planner',
    description: 'Planner',
    category: 'Productivity',
    tier: 'Tier 1 Auto',
  );

  const preview = SkillImportPreview(
    sourceUrl: 'https://example.com/SKILL.md',
    skill: skill,
    rawMarkdown: '---\nname: task_planner\n---\n',
    scan: SkillScanResult(),
  );

  late MockSkillsRegistryService registry;

  setUp(() {
    registry = MockSkillsRegistryService();
  });

  setUpAll(() {
    registerFallbackValue('fallback');
    registerFallbackValue(preview);
  });

  void stubLoadedRegistry() {
    when(() => registry.getAllSkills()).thenReturn(const <Skill>[skill]);
    when(() => registry.getActiveSkills()).thenReturn(const <Skill>[skill]);
  }

  group('SkillsCubit close race', () {
    test('loadSkills resolving after close does not throw', () async {
      final hydration = Completer<bool>();
      when(() => registry.hydrateFromStorage())
          .thenAnswer((_) => hydration.future);

      final cubit = SkillsCubit(skillsRegistryService: registry);
      await cubit.close();

      hydration.complete(true);
      await Future<void>.delayed(Duration.zero);

      expect(cubit.isClosed, isTrue);
    });

    test('loadSkills failing after close does not throw', () async {
      final hydration = Completer<bool>();
      when(() => registry.hydrateFromStorage())
          .thenAnswer((_) => hydration.future);

      final cubit = SkillsCubit(skillsRegistryService: registry);
      await cubit.close();

      hydration.completeError(StateError('hydration failed'));
      await Future<void>.delayed(Duration.zero);

      expect(cubit.isClosed, isTrue);
    });

    test('loadSkills still reaches SkillsLoaded while open', () async {
      final hydration = Completer<bool>();
      when(() => registry.hydrateFromStorage())
          .thenAnswer((_) => hydration.future);
      stubLoadedRegistry();

      final cubit = SkillsCubit(
        skillsRegistryService: registry,
        autoLoad: false,
      );
      final pending = cubit.loadSkills();
      hydration.complete(true);
      await pending;

      expect(cubit.state, isA<SkillsLoaded>());
      expect((cubit.state as SkillsLoaded).allSkills, const [skill]);
      await cubit.close();
    });

    test('loadSkills still reaches SkillsError while open', () async {
      when(() => registry.hydrateFromStorage())
          .thenThrow(StateError('storage down'));

      final cubit = SkillsCubit(
        skillsRegistryService: registry,
        autoLoad: false,
      );
      await cubit.loadSkills();

      expect(cubit.state, isA<SkillsError>());
      await cubit.close();
    });

    test('importSkillFromUrl on an already-closed cubit does not throw',
        () async {
      when(() => registry.hydrateFromStorage()).thenAnswer((_) async => true);
      stubLoadedRegistry();
      final importService = MockSkillImportService();

      final cubit = SkillsCubit(
        skillsRegistryService: registry,
        skillImportService: importService,
        autoLoad: false,
      );
      await cubit.loadSkills();
      await cubit.close();

      await cubit.importSkillFromUrl('https://example.com/SKILL.md');

      expect(cubit.isClosed, isTrue);
    });

    test('confirmSkillImport on an already-closed cubit does not throw',
        () async {
      when(() => registry.hydrateFromStorage()).thenAnswer((_) async => true);
      stubLoadedRegistry();
      final importService = MockSkillImportService();
      when(() => importService.buildPreview(any()))
          .thenAnswer((_) async => const Right(preview));

      final cubit = SkillsCubit(
        skillsRegistryService: registry,
        skillImportService: importService,
        autoLoad: false,
      );
      await cubit.loadSkills();
      await cubit.importSkillFromUrl('https://example.com/SKILL.md');
      await cubit.close();

      final result = await cubit.confirmSkillImport();

      expect(result, isNull);
      verifyNever(() => importService.confirmImport(any()));
    });

    test('importSkillFromUrl resolving after close does not throw', () async {
      when(() => registry.hydrateFromStorage()).thenAnswer((_) async => true);
      stubLoadedRegistry();
      final importService = MockSkillImportService();
      final build = Completer<Either<Failure, SkillImportPreview>>();
      when(() => importService.buildPreview(any()))
          .thenAnswer((_) => build.future);

      final cubit = SkillsCubit(
        skillsRegistryService: registry,
        skillImportService: importService,
        autoLoad: false,
      );
      await cubit.loadSkills();
      final pending =
          cubit.importSkillFromUrl('https://example.com/SKILL.md');
      await cubit.close();

      build.complete(const Right(preview));
      await pending;

      expect(cubit.isClosed, isTrue);
    });

    test('confirmSkillImport resolving after close does not throw', () async {
      when(() => registry.hydrateFromStorage()).thenAnswer((_) async => true);
      stubLoadedRegistry();
      final importService = MockSkillImportService();
      when(() => importService.buildPreview(any()))
          .thenAnswer((_) async => const Right(preview));
      final confirm = Completer<Either<Failure, Skill>>();
      when(() => importService.confirmImport(any()))
          .thenAnswer((_) => confirm.future);

      final cubit = SkillsCubit(
        skillsRegistryService: registry,
        skillImportService: importService,
        autoLoad: false,
      );
      await cubit.loadSkills();
      await cubit.importSkillFromUrl('https://example.com/SKILL.md');
      final pending = cubit.confirmSkillImport();
      await cubit.close();

      confirm.complete(const Right(skill));
      await pending;

      expect(cubit.isClosed, isTrue);
    });
  });
}
