import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';

import '../../../helpers/mocks.dart';

const Skill _storedSkill = Skill(
  id: 'skill_a',
  name: 'skill_a',
  description: 'A local skill used by storage failure tests.',
);

void main() {
  late MockSkillsLocalDatasource datasource;

  setUp(() {
    datasource = MockSkillsLocalDatasource();
  });

  test(
    'saveSkillState failure signals onStorageError without throwing',
    () async {
      final errors = <Object>[];
      final stacks = <StackTrace>[];
      final registry = SkillsRegistryService(
        loadDefaults: false,
        localDatasource: datasource,
        onStorageError: (error, stack) {
          errors.add(error);
          stacks.add(stack);
        },
      );
      registry.registerSkill(_storedSkill);
      when(
        () => datasource.saveSkillState(any(), any()),
      ).thenThrow(StateError('disk full'));

      registry.setSkillEnabled(_storedSkill.id, false);
      await Future<void>.delayed(Duration.zero);

      expect(errors, hasLength(1));
      expect(errors.single, isA<StateError>());
      expect((errors.single as StateError).message, 'disk full');
      expect(stacks, hasLength(1));
      expect(stacks.single, isNotNull);
    },
  );

  test('import persistence failure signals onStorageError', () async {
    final errors = <Object>[];
    final registry = SkillsRegistryService(
      loadDefaults: false,
      localDatasource: datasource,
      onStorageError: (error, stack) => errors.add(error),
    );
    when(
      () => datasource.saveImportedSkill(
        any(),
        sourceUrl: any(named: 'sourceUrl'),
      ),
    ).thenThrow(StateError('disk full'));

    await registry.registerImportedSkill(_storedSkill);

    expect(errors, hasLength(1));
    expect(errors.single, isA<StateError>());
    expect(registry.getSkill(_storedSkill.id), isNotNull);
  });

  test('failed hydration reports the error and stays retryable', () async {
    final errors = <Object>[];
    final registry = SkillsRegistryService(
      loadDefaults: false,
      localDatasource: datasource,
      onStorageError: (error, stack) => errors.add(error),
    );
    when(
      () => datasource.loadImportedSkills(),
    ).thenThrow(StateError('storage offline'));

    expect(await registry.hydrateFromStorage(), isFalse);
    expect(errors, hasLength(1));

    expect(await registry.hydrateFromStorage(), isFalse);
    expect(errors, hasLength(2));
    verify(() => datasource.loadImportedSkills()).called(2);
  });

  test('concurrent hydration shares one load', () async {
    final completer = Completer<List<Skill>>();
    final registry = SkillsRegistryService(
      loadDefaults: false,
      localDatasource: datasource,
    );
    when(
      () => datasource.loadImportedSkills(),
    ).thenAnswer((_) => completer.future);
    when(
      () => datasource.loadSkillStates(),
    ).thenAnswer((_) async => <String, bool>{});

    final first = registry.hydrateFromStorage();
    final second = registry.hydrateFromStorage();
    completer.complete(const <Skill>[]);

    expect(await Future.wait([first, second]), [true, true]);
    verify(() => datasource.loadImportedSkills()).called(1);
    verify(() => datasource.loadSkillStates()).called(1);
  });

  test('registry without onStorageError swallows failures as before', () async {
    final registry = SkillsRegistryService(
      loadDefaults: false,
      localDatasource: datasource,
    );
    registry.registerSkill(_storedSkill);
    when(
      () => datasource.loadImportedSkills(),
    ).thenThrow(StateError('storage offline'));
    when(
      () => datasource.saveSkillState(any(), any()),
    ).thenThrow(StateError('disk full'));

    expect(await registry.hydrateFromStorage(), isFalse);
    registry.setSkillEnabled(_storedSkill.id, false);
    await Future<void>.delayed(Duration.zero);
  });
}
