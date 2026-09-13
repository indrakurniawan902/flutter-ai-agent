import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/constant.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/settings_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSettingsCubit extends MockCubit<SettingsState> implements SettingsCubit {}
class MockServerProfileCubit extends MockCubit<ServerProfileState> implements ServerProfileCubit {}

void main() {
  late MockSettingsCubit mockSettingsCubit;
  late MockServerProfileCubit mockServerProfileCubit;

  final profile1 = ServerProfile(
    id: 'p1',
    name: 'VPS Oracle',
    gatewayUrl: 'https://indra-9router.my.id/v1',
    token: 'sk-token-1',
    isActive: true,
  );

  final profile2 = ServerProfile(
    id: 'p2',
    name: 'MacBook Pro',
    gatewayUrl: 'https://mbp.local:8080',
    token: 'sk-token-2',
    isActive: false,
  );

  setUpAll(() {
    registerFallbackValue(
      const ServerProfile(
        id: 'fallback',
        name: 'fallback',
        gatewayUrl: 'https://fallback.com',
        token: 'fallback',
      ),
    );
  });

  setUp(() {
    mockSettingsCubit = MockSettingsCubit();
    mockServerProfileCubit = MockServerProfileCubit();
    when(() => mockServerProfileCubit.state).thenReturn(
      const ServerProfileLoaded(profiles: [], activeProfile: null),
    );
    when(() => mockSettingsCubit.updateFromProfile(any()))
        .thenAnswer((_) {});
    when(() => mockServerProfileCubit.updateActiveProfile(
          gatewayUrl: any(named: 'gatewayUrl'),
          token: any(named: 'token'),
          model: any(named: 'model'),
          temperature: any(named: 'temperature'),
        )).thenAnswer((_) async {});
  });

  Widget buildTestWidget({
    SettingsCubit? cubit,
    ServerProfileCubit? profileCubit,
  }) {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: SettingsScreen(
        cubit: cubit ?? mockSettingsCubit,
        serverProfileCubit: profileCubit ?? mockServerProfileCubit,
      ),
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

    testWidgets('renders progressive tool pruning toggle reflecting settings state', (tester) async {
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

      final toggleFinder = find.byKey(const Key('settings_progressive_tool_pruning_toggle'));
      expect(toggleFinder, findsOneWidget);
      expect(
        tester.widget<SwitchListTile>(toggleFinder).value,
        isTrue,
      );

      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'sk-initial-key',
          model: 'ag-glm',
          temperature: 0.7,
          progressiveToolPruning: false,
        ),
      );
      // Unmount first so initState re-runs and picks up the new cubit state.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(
        tester.widget<SwitchListTile>(toggleFinder).value,
        isFalse,
      );
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
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      expect(find.text('Please enter a valid HTTP/HTTPS URL'), findsOneWidget);
      verifyNever(() => mockSettingsCubit.saveSettings(
            baseUrl: any(named: 'baseUrl'),
            apiKey: any(named: 'apiKey'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
            progressiveToolPruning: any(named: 'progressiveToolPruning'),
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
      await tester.ensureVisible(saveButton);
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
            progressiveToolPruning: any(named: 'progressiveToolPruning'),
          )).thenAnswer((_) async => true);

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final saveButton = find.byKey(const Key('settings_save_button'));
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pump();

      verify(() => mockSettingsCubit.saveSettings(
            baseUrl: 'https://indra-9router.my.id/v1',
            apiKey: 'sk-valid-key',
            model: 'ag-glm',
            temperature: 0.7,
            progressiveToolPruning: true,
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

  group('SettingsScreen - Server Profile Switcher', () {
    testWidgets('renders server profile switcher UI components', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: '«reda...…»',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockServerProfileCubit.state).thenReturn(
        ServerProfileLoaded(
          profiles: [profile1, profile2],
          activeProfile: profile1,
        ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byKey(const Key('settings_server_profile_dropdown')), findsOneWidget);
      expect(find.byKey(const Key('settings_add_profile_button')), findsOneWidget);
      expect(find.text('VPS Oracle (Active)'), findsOneWidget);
    });

    testWidgets('selecting a profile in dropdown calls switchActiveProfile', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: '«reda...…»',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockServerProfileCubit.state).thenReturn(
        ServerProfileLoaded(
          profiles: [profile1, profile2],
          activeProfile: profile1,
        ),
      );
      when(() => mockServerProfileCubit.switchActiveProfile('p2'))
          .thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final dropdown = find.byKey(const Key('settings_server_profile_dropdown'));
      await tester.tap(dropdown);
      await tester.pumpAndSettle();

      final option = find.text('MacBook Pro').last;
      await tester.tap(option);
      await tester.pumpAndSettle();

      verify(() => mockServerProfileCubit.switchActiveProfile('p2')).called(1);
    });

    testWidgets('tapping add server profile button opens dialog and submitting calls addProfile', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: '«reda...…»',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockServerProfileCubit.state).thenReturn(
        const ServerProfileLoaded(profiles: [], activeProfile: null),
      );
      when(() => mockServerProfileCubit.addProfile(
            name: 'Local Dev',
            gatewayUrl: 'http://localhost:8080',
            token: 'sk-local',
            makeActive: true,
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
          )).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final addButton = find.byKey(const Key('settings_add_profile_button'));
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_profile_name_field')), findsOneWidget);
      expect(find.byKey(const Key('add_profile_url_field')), findsOneWidget);
      expect(find.byKey(const Key('add_profile_token_field')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('add_profile_name_field')), 'Local Dev');
      await tester.enterText(find.byKey(const Key('add_profile_url_field')), 'http://localhost:8080');
      await tester.enterText(find.byKey(const Key('add_profile_token_field')), 'sk-local');

      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pumpAndSettle();

      verify(() => mockServerProfileCubit.addProfile(
            name: 'Local Dev',
            gatewayUrl: 'http://localhost:8080',
            token: 'sk-local',
            makeActive: true,
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
          )).called(1);
    });

    testWidgets('tapping delete profile button calls deleteProfile on active profile', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: '«reda...…»',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockServerProfileCubit.state).thenReturn(
        ServerProfileLoaded(
          profiles: [profile1, profile2],
          activeProfile: profile1,
        ),
      );
      when(() => mockServerProfileCubit.deleteProfile('p1'))
          .thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final deleteButton = find.byKey(const Key('settings_delete_profile_button'));
      expect(deleteButton, findsOneWidget);
      await tester.tap(deleteButton);
      await tester.pumpAndSettle();

      verify(() => mockServerProfileCubit.deleteProfile('p1')).called(1);
    });

    testWidgets('displays SnackBar message when ServerProfileOperationSuccess is emitted', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: '«reda...…»',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );

      whenListen(
        mockServerProfileCubit,
        Stream.fromIterable([
          ServerProfileOperationSuccess(
            profiles: [profile1],
            activeProfile: profile1,
            message: 'Switched to profile "VPS Oracle"',
          ),
        ]),
        initialState: const ServerProfileLoaded(profiles: [], activeProfile: null),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Switched to profile "VPS Oracle"'), findsOneWidget);
    });

    testWidgets('displays SnackBar error message when ServerProfileError is emitted', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'test-api-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );

      whenListen(
        mockServerProfileCubit,
        Stream.fromIterable([
          const ServerProfileError(
            profiles: [],
            activeProfile: null,
            message: 'Failed to delete profile',
          ),
        ]),
        initialState: const ServerProfileLoaded(profiles: [], activeProfile: null),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Failed to delete profile'), findsOneWidget);
    });

    testWidgets('tapping cancel in add profile dialog closes dialog without calling addProfile', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'test-api-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockServerProfileCubit.state).thenReturn(
        const ServerProfileLoaded(profiles: [], activeProfile: null),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final addButton = find.byKey(const Key('settings_add_profile_button'));
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      expect(find.text('Add Server Profile'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Add Server Profile'), findsNothing);
      verifyNever(() => mockServerProfileCubit.addProfile(
            name: any(named: 'name'),
            gatewayUrl: any(named: 'gatewayUrl'),
            token: any(named: 'token'),
            makeActive: any(named: 'makeActive'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
          ));
    });

    testWidgets('submitting add profile dialog with invalid inputs shows errors', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'test-api-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockServerProfileCubit.state).thenReturn(
        const ServerProfileLoaded(profiles: [], activeProfile: null),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final addButton = find.byKey(const Key('settings_add_profile_button'));
      await tester.tap(addButton);
      await tester.pumpAndSettle();

      // Submit empty form
      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Name cannot be empty'), findsOneWidget);
      expect(find.text('URL cannot be empty'), findsOneWidget);
      expect(find.text('Token cannot be empty'), findsOneWidget);

      // Enter invalid URL
      await tester.enterText(find.byKey(const Key('add_profile_url_field')), 'invalid-url');
      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid HTTP/HTTPS/WS/WSS URL'), findsOneWidget);
      verifyNever(() => mockServerProfileCubit.addProfile(
            name: any(named: 'name'),
            gatewayUrl: any(named: 'gatewayUrl'),
            token: any(named: 'token'),
            makeActive: any(named: 'makeActive'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
          ));
    });

    testWidgets('accepts gateway URLs in all four normalizable schemes', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'sk-valid-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockServerProfileCubit.state).thenReturn(
        const ServerProfileLoaded(profiles: [], activeProfile: null),
      );

      // A gateway endpoint IS a WebSocket endpoint; http/https/ws/wss are all
      // rewritten by GatewayClient.normalizeGatewayUri, so the form must admit
      // every one of them.
      const gatewayUrls = [
        'wss://hermes.indra-developer.my.id/device/ws',
        'https://hermes.indra-developer.my.id',
        'ws://192.168.1.10:18789/device/ws',
        'http://192.168.1.10:8644',
      ];

      for (final url in gatewayUrls) {
        when(() => mockServerProfileCubit.addProfile(
              name: 'Bridge',
              gatewayUrl: url,
              token: 'sk-bridge-token',
              makeActive: true,
              model: 'ag-glm',
              temperature: 0.7,
            )).thenAnswer((_) async {});

        await tester.pumpWidget(buildTestWidget());
        await tester.pump();

        await tester.tap(find.byKey(const Key('settings_add_profile_button')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('add_profile_name_field')),
          'Bridge',
        );
        await tester.enterText(
          find.byKey(const Key('add_profile_url_field')),
          url,
        );
        await tester.enterText(
          find.byKey(const Key('add_profile_token_field')),
          'sk-bridge-token',
        );
        await tester.enterText(
          find.byKey(const Key('add_profile_model_field')),
          'ag-glm',
        );

        await tester.tap(find.byKey(const Key('add_profile_submit_button')));
        await tester.pumpAndSettle();

        expect(
          find.text('Enter a valid HTTP/HTTPS/WS/WSS URL'),
          findsNothing,
          reason: '$url must pass validation',
        );
        verify(() => mockServerProfileCubit.addProfile(
              name: 'Bridge',
              gatewayUrl: url,
              token: 'sk-bridge-token',
              makeActive: true,
              model: 'ag-glm',
              temperature: 0.7,
            )).called(1);
      }
    });

    testWidgets('still rejects junk and empty gateway URLs', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'sk-valid-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockServerProfileCubit.state).thenReturn(
        const ServerProfileLoaded(profiles: [], activeProfile: null),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.tap(find.byKey(const Key('settings_add_profile_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('add_profile_name_field')),
        'Bridge',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_token_field')),
        'sk-bridge-token',
      );

      // Non-URL junk.
      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'not a url',
      );
      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Enter a valid HTTP/HTTPS/WS/WSS URL'), findsOneWidget);

      // Empty.
      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        '',
      );
      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('URL cannot be empty'), findsOneWidget);

      verifyNever(() => mockServerProfileCubit.addProfile(
            name: any(named: 'name'),
            gatewayUrl: any(named: 'gatewayUrl'),
            token: any(named: 'token'),
            makeActive: any(named: 'makeActive'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
          ));
    });

    testWidgets('gateway URL field hints at a WebSocket gateway endpoint',
        (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'sk-valid-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockServerProfileCubit.state).thenReturn(
        const ServerProfileLoaded(profiles: [], activeProfile: null),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.tap(find.byKey(const Key('settings_add_profile_button')));
      await tester.pumpAndSettle();

      final inner = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('add_profile_url_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(
        inner.decoration?.hintText,
        'wss://hermes.indra-developer.my.id/device/ws',
      );
    });

    testWidgets(
        'updates model and temperature fields and calls updateFromProfile when ServerProfileOperationSuccess emitted',
        (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://old-url.com/v1',
          apiKey: 'sk-old-key',
          model: 'old-model',
          temperature: 0.7,
        ),
      );

      final customProfile = ServerProfile(
        id: 'p-custom',
        name: 'Custom Server',
        gatewayUrl: 'https://custom-server.com/v1',
        token: 'sk-custom-token',
        isActive: true,
        model: 'custom-model-x',
        temperature: 1.2,
      );

      whenListen(
        mockServerProfileCubit,
        Stream.fromIterable([
          ServerProfileOperationSuccess(
            profiles: [customProfile],
            activeProfile: customProfile,
            message: 'Switched to profile "Custom Server"',
          ),
        ]),
        initialState: const ServerProfileLoaded(profiles: [], activeProfile: null),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final modelField = tester.widget<TextFormField>(
        find.byKey(const Key('settings_model_field')),
      );
      expect(modelField.controller?.text, 'custom-model-x');

      final tempField = tester.widget<TextFormField>(
        find.byKey(const Key('settings_temperature_field')),
      );
      expect(tempField.controller?.text, '1.2');

      final baseUrlField = tester.widget<TextFormField>(
        find.byKey(const Key('settings_base_url_field')),
      );
      expect(baseUrlField.controller?.text, 'https://custom-server.com/v1');

      final apiKeyField = tester.widget<TextFormField>(
        find.byKey(const Key('settings_api_key_field')),
      );
      expect(apiKeyField.controller?.text, 'sk-custom-token');

      verify(() => mockSettingsCubit.updateFromProfile(customProfile)).called(1);
    });
  });

  group('SettingsScreen - Add Profile Model & Temperature', () {
    testWidgets('add profile dialog renders model and temperature fields with defaults', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'test-api-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockServerProfileCubit.state).thenReturn(
        const ServerProfileLoaded(profiles: [], activeProfile: null),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.tap(find.byKey(const Key('settings_add_profile_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_profile_model_field')), findsOneWidget);
      expect(
        find.byKey(const Key('add_profile_temperature_field')),
        findsOneWidget,
      );

      final modelField = tester.widget<TextFormField>(
        find.byKey(const Key('add_profile_model_field')),
      );
      expect(modelField.controller?.text, AppConstants.defaultModel);

      final tempField = tester.widget<TextFormField>(
        find.byKey(const Key('add_profile_temperature_field')),
      );
      expect(
        tempField.controller?.text,
        AppConstants.defaultTemperature.toString(),
      );
    });

    testWidgets('submitting add profile dialog forwards model and temperature to addProfile', (tester) async {
      when(() => mockSettingsCubit.state).thenReturn(
        const SettingsLoaded(
          baseUrl: 'https://indra-9router.my.id/v1',
          apiKey: 'test-api-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );
      when(() => mockServerProfileCubit.state).thenReturn(
        const ServerProfileLoaded(profiles: [], activeProfile: null),
      );
      when(() => mockServerProfileCubit.addProfile(
            name: 'Custom Dev',
            gatewayUrl: 'http://localhost:8080',
            token: 'sk-custom',
            makeActive: true,
            model: 'gpt-4o-mini',
            temperature: 0.3,
          )).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.tap(find.byKey(const Key('settings_add_profile_button')));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('add_profile_name_field')),
        'Custom Dev',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'http://localhost:8080',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_token_field')),
        'sk-custom',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_model_field')),
        'gpt-4o-mini',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_temperature_field')),
        '0.3',
      );

      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pumpAndSettle();

      verify(() => mockServerProfileCubit.addProfile(
            name: 'Custom Dev',
            gatewayUrl: 'http://localhost:8080',
            token: 'sk-custom',
            makeActive: true,
            model: 'gpt-4o-mini',
            temperature: 0.3,
          )).called(1);
    });

    testWidgets('saving settings also updates the active server profile', (tester) async {
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
            progressiveToolPruning: any(named: 'progressiveToolPruning'),
          )).thenAnswer((_) async => true);
      when(() => mockServerProfileCubit.updateActiveProfile(
            gatewayUrl: 'https://indra-9router.my.id/v1',
            token: 'sk-valid-key',
            model: 'ag-glm',
            temperature: 0.7,
          )).thenAnswer((_) async {});

      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      final saveButton = find.byKey(const Key('settings_save_button'));
      await tester.ensureVisible(saveButton);
      await tester.tap(saveButton);
      await tester.pumpAndSettle();

      verify(() => mockServerProfileCubit.updateActiveProfile(
            gatewayUrl: 'https://indra-9router.my.id/v1',
            token: 'sk-valid-key',
            model: 'ag-glm',
            temperature: 0.7,
          )).called(1);
    });
  });
}
