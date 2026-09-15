import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final androidDir = Directory('android');
  final skipReason = androidDir.existsSync()
      ? null
      : 'android/ not found; run from repo root';

  group('Android build has no product flavors', () {
    test('build.gradle.kts drops every flavor declaration', () {
      if (skipReason != null) {
        markTestSkipped(skipReason);
        return;
      }

      // Arrange
      final gradleFile = File('android/app/build.gradle.kts');

      // Act
      final source = gradleFile.readAsStringSync();

      // Assert
      expect(source, isNot(contains('productFlavors')));
      expect(source, isNot(contains('flavorDimensions')));
      expect(source, isNot(contains('applicationIdSuffix')));
      expect(source, isNot(contains('dimension =')));
    });

    test('build.gradle.kts keeps the single production applicationId', () {
      if (skipReason != null) {
        markTestSkipped(skipReason);
        return;
      }

      // Arrange
      final gradleFile = File('android/app/build.gradle.kts');

      // Act
      final source = gradleFile.readAsStringSync();

      // Assert
      expect(source, contains('applicationId = "ai.hermes.flames"'));
      expect(source, contains('id("dev.flutter.flutter-gradle-plugin")'));
    });
  });

  group('App name resolves from the main resource', () {
    test('main strings.xml declares app_name and no app_flavor', () {
      if (skipReason != null) {
        markTestSkipped(skipReason);
        return;
      }

      // Arrange
      final stringsFile = File('android/app/src/main/res/values/strings.xml');

      // Act
      final source = stringsFile.readAsStringSync();

      // Assert
      expect(stringsFile.existsSync(), isTrue);
      expect(source, contains('<string name="app_name">Flames</string>'));
      expect(source, isNot(contains('app_flavor')));
    });

    test('flavor-specific strings.xml resources are gone', () {
      if (skipReason != null) {
        markTestSkipped(skipReason);
        return;
      }

      // Arrange
      final developmentStrings =
          File('android/app/src/development/res/values/strings.xml');
      final productionStrings =
          File('android/app/src/production/res/values/strings.xml');

      // Act & Assert
      expect(developmentStrings.existsSync(), isFalse);
      expect(productionStrings.existsSync(), isFalse);
    });

    test('AndroidManifest still labels the app with @string/app_name', () {
      if (skipReason != null) {
        markTestSkipped(skipReason);
        return;
      }

      // Arrange
      final manifestFile = File('android/app/src/main/AndroidManifest.xml');

      // Act
      final source = manifestFile.readAsStringSync();

      // Assert
      expect(source, contains('android:label="@string/app_name"'));
    });
  });
}
