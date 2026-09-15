import 'dart:convert';
import 'dart:io';

import 'package:flutter_ai_agent/myapp.dart';
import 'package:flutter_test/flutter_test.dart';

import 'helpers/repo_root.dart';

void main() {
  final repoRoot = resolveRepoRoot();
  String repoPath(String relative) => '${repoRoot.path}/$relative';

  group('Single entrypoint', () {
    test('bootstrap is a zero-argument Future<void> function', () {
      // Arrange & Act
      final Future<void> Function() entrypoint = bootstrap;

      // Assert
      expect(identical(entrypoint, bootstrap), isTrue);
    });

    test('lib/main.dart declares a zero-argument void main calling bootstrap',
        () {
      // Arrange
      final mainFile = File(repoPath('lib/main.dart'));
      expect(
        mainFile.existsSync(),
        isTrue,
        reason: '${mainFile.path} must exist',
      );

      // Act
      final source = mainFile.readAsStringSync();

      // Assert
      expect(source, contains('bootstrap()'));
      expect(source, matches(RegExp(r'void\s+main\s*\(\s*\)')));
    });
  });

  group('No flavor config', () {
    test('flavor leftovers are absent from every lib/ dart file', () {
      // Arrange
      final libDir = Directory(repoPath('lib'));
      expect(
        libDir.existsSync(),
        isTrue,
        reason: '${libDir.path} must exist',
      );
      final leftovers = <String>[
        'FlavorConfig',
        'FlavorConfig.current',
        'main_development',
        'main_production',
      ];

      // Act
      final dartFiles = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList();
      final violations = <String>[];
      for (final file in dartFiles) {
        final source = file.readAsStringSync();
        for (final leftover in leftovers) {
          if (source.contains(leftover)) {
            violations.add('${file.path}: $leftover');
          }
        }
      }

      // Assert
      expect(dartFiles, isNotEmpty);
      expect(violations, isEmpty);
    });

    test('lib/common/flavor_config.dart does not exist', () {
      // Arrange & Act
      final flavorConfig = File(repoPath('lib/common/flavor_config.dart'));

      // Assert
      expect(flavorConfig.existsSync(), isFalse);
    });
  });

  group('App root', () {
    test('const MyApp() still constructs', () {
      // Arrange & Act
      const app = MyApp();

      // Assert
      expect(app, isA<MyApp>());
      expect(app.router, isNull);
    });
  });

  group('Tooling and docs carry no flavor references', () {
    test('every .vscode config mentions no flavor and no deleted entrypoint',
        () {
      // Arrange
      final vscodeDir = Directory(repoPath('.vscode'));
      expect(
        vscodeDir.existsSync(),
        isTrue,
        reason: '${vscodeDir.path} must exist',
      );
      final banned = <String>[
        'flavor',
        'main_development',
        'main_production',
      ];

      // Act
      final configFiles = vscodeDir
          .listSync(recursive: true)
          .whereType<File>()
          .toList();
      final violations = <String>[];
      for (final file in configFiles) {
        final source = file.readAsStringSync().toLowerCase();
        for (final token in banned) {
          if (source.contains(token)) {
            violations.add('${file.path}: $token');
          }
        }
      }

      // Assert
      expect(configFiles, isNotEmpty);
      expect(violations, isEmpty);
    });

    test('docs and repo-root markdown keep no banned flavor identifiers', () {
      // Arrange
      final docsDir = Directory(repoPath('docs'));
      expect(
        docsDir.existsSync(),
        isTrue,
        reason: '${docsDir.path} must exist',
      );
      final banned = <String>[
        'FlavorConfig',
        'main_development',
        'main_production',
        '--flavor',
      ];

      // Act
      final docFiles = <File>[
        // Repo-root markdown is in scope too: the de-flavor card's grep list
        // and this guard both omitted it, so AGENTS.md kept documenting the
        // deleted --flavor commands after every other reference was fixed.
        ...Directory(repoRoot.path)
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.md'))
            .where((file) => !file.path.split('/').last.startsWith('.')),
        ...docsDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.md')),
      ];
      final violations = <String>[];
      for (final file in docFiles) {
        final source = file.readAsStringSync();
        for (final token in banned) {
          if (source.contains(token)) {
            violations.add('${file.path}: $token');
          }
        }
      }

      // Assert
      expect(docFiles, isNotEmpty);
      expect(violations, isEmpty);
    });

    test('launch.json is valid JSON with two lib/main.dart configurations',
        () {
      // Arrange
      final launchFile = File(repoPath('.vscode/launch.json'));
      expect(
        launchFile.existsSync(),
        isTrue,
        reason: '${launchFile.path} must exist',
      );

      // Act
      final decoded = jsonDecode(launchFile.readAsStringSync());
      final configurations =
          (decoded as Map<String, dynamic>)['configurations'] as List<dynamic>;

      // Assert
      expect(configurations, hasLength(2));
      for (final configuration in configurations) {
        expect(
          (configuration as Map<String, dynamic>)['program'],
          'lib/main.dart',
        );
      }
    });

    test('tasks.json is valid JSON and no task passes --flavor', () {
      // Arrange
      final tasksFile = File(repoPath('.vscode/tasks.json'));
      expect(
        tasksFile.existsSync(),
        isTrue,
        reason: '${tasksFile.path} must exist',
      );

      // Act
      final decoded = jsonDecode(tasksFile.readAsStringSync());
      final tasks = (decoded as Map<String, dynamic>)['tasks'] as List<dynamic>;

      // Assert
      expect(tasks, isNotEmpty);
      for (final task in tasks) {
        final args =
            (task as Map<String, dynamic>)['args'] as List<dynamic>? ?? [];
        expect(args, isNot(contains('--flavor')));
      }
    });

    test('single entrypoint exists while the flavor entrypoints are gone', () {
      // Arrange
      final mainFile = File(repoPath('lib/main.dart'));
      expect(
        mainFile.existsSync(),
        isTrue,
        reason: '${mainFile.path} must exist',
      );

      // Act
      final removedFiles = <File>[
        File(repoPath('lib/main_development.dart')),
        File(repoPath('lib/main_production.dart')),
        File(repoPath('lib/common/flavor_config.dart')),
      ];

      // Assert
      for (final file in removedFiles) {
        expect(file.existsSync(), isFalse, reason: '${file.path} must be gone');
      }
    });

    test('architecture.md documents the flavors-off-by-default policy', () {
      // Arrange
      final architectureFile = File(repoPath('docs/architecture.md'));
      expect(
        architectureFile.existsSync(),
        isTrue,
        reason: '${architectureFile.path} must exist',
      );

      // Act
      final source = architectureFile.readAsStringSync();

      // Assert
      expect(
        source,
        matches(
          RegExp(
            r'## 3\. Entrypoint \(single, no flavors\)'
            r'[\s\S]*?lib/main\.dart'
            r'[\s\S]*?off by default',
          ),
        ),
        reason: 'the single-entrypoint section must name lib/main.dart and '
            'state that flavors are off by default',
      );
    });
  });
}
