import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/theme/app_theme.dart';
import 'package:flutter_ai_agent/features/settings/domain/settings_cubit.dart';
import 'package:flutter_ai_agent/features/settings/domain/settings_state.dart';
import 'package:flutter_ai_agent/features/settings/presentation/screens/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSettingsCubit extends MockCubit<SettingsState> implements SettingsCubit {}

void main() {
  late MockSettingsCubit mockSettingsCubit;

  setUp(() {
    mockSettingsCubit = MockSettingsCubit();
  });

  Widget buildTestWidget({SettingsCubit? cubit}) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: SettingsScreen(cubit: cubit ?? mockSettingsCubit),
    );
  }

  group('SettingsScreen - Rendering & Initial State', () {
    testWidgets('renders all required input fields and save button', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'sk-initial-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byKey(const Key('settings_base_url_field')), findsOneWidget);
      expect(find.byKey(const Key('settings_api_key_field')), findsOneWidget);
      expect(find.byKey(const Key('settings_model_field')), findsOneWidget);
      expect(find.byKey(const Key('settings_temperature_field')), findsOneWidget);
      expect(find.byKey(const Key('settings_save_button')), findsOneWidget);
      expect(find.byKey(const Key('settings_qr_scanner_button')), findsOneWidget);
      expect(find.byKey(const Key('settings_pair_qr_button')), findsOneWidget);

      final baseUrlField = tester.widget<TextFormField>(
        find.byKey(const Key('settings_base_url_field')),
      );
      expect(baseUrlField.controller?.text, 'https://indra-9router.my.id/v1');

      final apiKeyField = tester.widget<TextFormField>(
        find.byKey(const Key('settings_api_key_field')),
      );
      expect(apiKeyField.controller?.text, 'sk-initial-key');

      final modelField = tester.widget<TextFormField>(
        find.byKey(const Key('settings_model_field')),
      );
      expect(modelField.controller?.text, 'ag-glm');

      final tempField = tester.widget<TextFormField>(
        find.byKey(const Key('settings_temperature_field')),
      );
      expect(tempField.controller?.text, '0.7');
    });

    testWidgets('toggles API key obscureText when visibility icon is tapped', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'sk-secret-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final apiKeyFinder = find.byKey(const Key('settings_api_key_field'));
      var editableText = tester.widget<EditableText>(
        find.descendant(of: apiKeyFinder, matching: find.byType(EditableText)),
      );
      expect(editableText.obscureText, isTrue);

      final toggleFinder = find.byKey(const Key('settings_toggle_api_key_visibility'));
      expect(toggleFinder, findsOneWidget);
      await tester.tap(toggleFinder);
      await tester.pump();

      editableText = tester.widget<EditableText>(
        find.descendant(of: apiKeyFinder, matching: find.byType(EditableText)),
      );
      expect(editableText.obscureText, isFalse);
    });
  });

  group('SettingsScreen - Validation & Actions', () {
    testWidgets('shows validation error when Base URL is empty', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: '',
          apiKey: 'sk-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final saveButton = find.byKey(const Key('settings_save_button'));
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid HTTP/HTTPS URL'), findsOneWidget);
      verifyNever(() => mockSettingsCubit.saveSettings(
            baseUrl: any(named: 'baseUrl'),
            apiKey: any(named: 'apiKey'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
          ));
    });

    testWidgets('shows validation error when API Key is empty', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://valid-url.com/v1',
          apiKey: '',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final saveButton = find.byKey(const Key('settings_save_button'));
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('API Key cannot be empty'), findsOneWidget);
    });

    testWidgets('calls saveSettings when valid data is submitted', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'sk-valid-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockSettingsCubit.saveSettings(
            baseUrl: any(named: 'baseUrl'),
            apiKey: any(named: 'apiKey'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
          )).thenAnswer((_) async => true);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final saveButton = find.byKey(const Key('settings_save_button'));
      await tester.tap(saveButton);
      await tester.pump();

      verify(() => mockSettingsCubit.saveSettings(
            baseUrl: 'https://indra-9router.my.id/v1',
            apiKey: 'sk-valid-key',
            model: 'ag-glm',
            temperature: 0.7,
          )).called(1);
    });

    testWidgets('displays SnackBar message when SettingsSuccess is emitted', (tester) async {
      whenListen(
        mockSettingsCubit,
        Stream.fromIterable([
          const SettingsSuccess(
            baseUrl: 'https://indra-9router.my.id/v1',
            apiKey: 'sk-key',
            model: 'ag-glm',
            temperature: 0.7,
            message: 'Settings saved successfully',
          ),
        ]),
        initialState: const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'sk-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Settings saved successfully'), findsOneWidget);
    });

    testWidgets('calls resetToDefaults when reset button in AppBar is tapped', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'sk-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockSettingsCubit.resetToDefaults()).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final resetButton = find.byKey(const Key('settings_reset_button'));
      expect(resetButton, findsOneWidget);
      await tester.tap(resetButton);
      await tester.pump();

      verify(() => mockSettingsCubit.resetToDefaults()).called(1);
    });
  });
}
