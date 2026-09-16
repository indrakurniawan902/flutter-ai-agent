import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/repo_root.dart';

void main() {
  final repoRoot = resolveRepoRoot();
  String repoPath(String relative) => '${repoRoot.path}/$relative';

  group('Android build has no product flavors', () {
    test('build.gradle.kts drops every flavor declaration', () {
      // Arrange
      final gradleFile = File(repoPath('android/app/build.gradle.kts'));
      expect(
        gradleFile.existsSync(),
        isTrue,
        reason: '${gradleFile.path} must exist',
      );

      // Act
      final source = gradleFile.readAsStringSync();

      // Assert
      expect(source, isNot(contains('productFlavors')));
      expect(source, isNot(contains('flavorDimensions')));
      expect(source, isNot(contains('applicationIdSuffix')));
      expect(source, isNot(contains('dimension =')));
    });

    test('build.gradle.kts keeps the single production applicationId', () {
      // Arrange
      final gradleFile = File(repoPath('android/app/build.gradle.kts'));
      expect(
        gradleFile.existsSync(),
        isTrue,
        reason: '${gradleFile.path} must exist',
      );

      // Act
      final source = gradleFile.readAsStringSync();

      // Assert
      expect(source, contains('applicationId = "ai.hermes.flames"'));
      expect(source, contains('id("dev.flutter.flutter-gradle-plugin")'));
    });
  });

  group('App name resolves from the main resource', () {
    test('main strings.xml declares app_name and no app_flavor', () {
      // Arrange
      final stringsFile =
          File(repoPath('android/app/src/main/res/values/strings.xml'));
      expect(
        stringsFile.existsSync(),
        isTrue,
        reason: '${stringsFile.path} must exist',
      );

      // Act
      final source = stringsFile.readAsStringSync();

      // Assert
      expect(source, contains('<string name="app_name">Flames</string>'));
      expect(source, isNot(contains('app_flavor')));
    });

    test('flavor-specific strings.xml resources are gone', () {
      // Arrange
      final developmentStrings = File(
        repoPath('android/app/src/development/res/values/strings.xml'),
      );
      final productionStrings = File(
        repoPath('android/app/src/production/res/values/strings.xml'),
      );

      // Act & Assert
      expect(developmentStrings.existsSync(), isFalse);
      expect(productionStrings.existsSync(), isFalse);
    });

    test('AndroidManifest still labels the app with @string/app_name', () {
      // Arrange
      final manifestFile =
          File(repoPath('android/app/src/main/AndroidManifest.xml'));
      expect(
        manifestFile.existsSync(),
        isTrue,
        reason: '${manifestFile.path} must exist',
      );

      // Act
      final source = manifestFile.readAsStringSync();

      // Assert
      expect(source, contains('android:label="@string/app_name"'));
    });
  });
}
