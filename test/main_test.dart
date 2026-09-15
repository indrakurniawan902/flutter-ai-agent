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
}
