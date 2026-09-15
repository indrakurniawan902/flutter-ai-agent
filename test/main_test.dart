import 'dart:convert';
import 'dart:io';

import 'package:flutter_ai_agent/myapp.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Single entrypoint', () {
    test('bootstrap is a zero-argument Future<void> function', () {
      // Arrange & Act
      final Future<void> Function() entrypoint = bootstrap;

      // Assert
      expect(entrypoint, isNotNull);
    });

    test('lib/main.dart declares a zero-argument void main calling bootstrap',
        () {
      // Arrange
      final mainFile = File('lib/main.dart');
      if (!mainFile.existsSync()) {
        markTestSkipped('lib/main.dart not found; run from repo root');
        return;
      }

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
      final libDir = Directory('lib');
      if (!libDir.existsSync()) {
        markTestSkipped('lib/ not found; run from repo root');
        return;
      }
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
      final flavorConfig = File('lib/common/flavor_config.dart');

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
      final vscodeDir = Directory('.vscode');
      if (!vscodeDir.existsSync()) {
        markTestSkipped('.vscode/ not found; run from repo root');
        return;
      }
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

    test('docs keep no banned flavor identifiers or --flavor flags', () {
      // Arrange
      final docsDir = Directory('docs');
      if (!docsDir.existsSync()) {
        markTestSkipped('docs/ not found; run from repo root');
        return;
      }
      final banned = <String>[
        'FlavorConfig',
        'main_development',
        'main_production',
        '--flavor',
      ];

      // Act
      final docFiles = docsDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.md'))
          .toList();
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
      final launchFile = File('.vscode/launch.json');
      if (!launchFile.existsSync()) {
        markTestSkipped('.vscode/launch.json not found; run from repo root');
        return;
      }

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
      final tasksFile = File('.vscode/tasks.json');
      if (!tasksFile.existsSync()) {
        markTestSkipped('.vscode/tasks.json not found; run from repo root');
        return;
      }

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
      final mainFile = File('lib/main.dart');
      if (!mainFile.existsSync()) {
        markTestSkipped('lib/main.dart not found; run from repo root');
        return;
      }

      // Act
      final removedFiles = <File>[
        File('lib/main_development.dart'),
        File('lib/main_production.dart'),
        File('lib/common/flavor_config.dart'),
      ];

      // Assert
      for (final file in removedFiles) {
        expect(file.existsSync(), isFalse, reason: '${file.path} must be gone');
      }
    });

    test('architecture.md documents the flavors-off-by-default policy', () {
      // Arrange
      final architectureFile = File('docs/architecture.md');
      if (!architectureFile.existsSync()) {
        markTestSkipped('docs/architecture.md not found; run from repo root');
        return;
      }

      // Act
      final source = architectureFile.readAsStringSync();

      // Assert
      expect(source, contains('off by default'));
    });
  });
}
