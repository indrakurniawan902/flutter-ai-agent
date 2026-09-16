import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';

import '../../../helpers/mocks.dart';

const Skill _storedSkill = Skill(
  id: 'skill_a',
  name: 'skill_a',
  description: 'A local skill used by hydration concurrency tests.',
);

void main() {
  late MockSkillsLocalDatasource datasource;

  setUp(() {
    datasource = MockSkillsLocalDatasource();
  });

  test(
    'concurrent callers share one future and both get the real result',
    () async {
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
      expect(identical(first, second), isTrue);

      completer.complete(const <Skill>[_storedSkill]);

      final results = await Future.wait([first, second]);
      expect(results, [true, true]);
      verify(() => datasource.loadImportedSkills()).called(1);
      expect(registry.getSkill(_storedSkill.id), isNotNull);
    },
  );

  test(
    'failed hydration signals, then a later call retries and succeeds',
    () async {
      final errors = <Object>[];
      final registry = SkillsRegistryService(
        loadDefaults: false,
        localDatasource: datasource,
        onStorageError: (error, stack) => errors.add(error),
      );
      var attempts = 0;
      when(() => datasource.loadImportedSkills()).thenAnswer((_) async {
        attempts++;
        if (attempts == 1) {
          throw StateError('storage offline');
        }
        return const <Skill>[_storedSkill];
      });
      when(
        () => datasource.loadSkillStates(),
      ).thenAnswer((_) async => <String, bool>{});

      expect(await registry.hydrateFromStorage(), isFalse);
      expect(errors, hasLength(1));

      expect(await registry.hydrateFromStorage(), isTrue);
      verify(() => datasource.loadImportedSkills()).called(2);
      expect(registry.getSkill(_storedSkill.id), isNotNull);
    },
  );

  test('no datasource returns false without throwing', () async {
    final registry = SkillsRegistryService(loadDefaults: false);

    expect(await registry.hydrateFromStorage(), isFalse);
  });
}
