import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/services/settings/server_profile_probe_service.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/add_profile_screen.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

class MockServerProfileCubit extends MockCubit<ServerProfileState>
    implements ServerProfileCubit {}

class MockProbeService extends Mock implements ServerProfileProbeService {}

void main() {
  late MockServerProfileCubit cubit;
  late MockProbeService probe;

  setUpAll(() {
    registerFallbackValue(ServerProfileKind.hermesAgent);
    registerFallbackValue(
      const ServerProfile(
        id: 'fallback',
        name: 'fallback',
        gatewayUrl: 'https://fallback.example.com',
        token: 'fallback',
      ),
    );
  });

  setUp(() {
    cubit = MockServerProfileCubit();
    probe = MockProbeService();
    when(() => cubit.state).thenReturn(
      const ServerProfileLoaded(profiles: [], activeProfile: null),
    );
  });

  Widget buildTestWidget({
    ServerProfileCubit? profileCubit,
    ServerProfileProbeService? probeService,
  }) =>
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: AddProfileScreen(
          serverProfileCubit: profileCubit ?? cubit,
          probeService: probeService ?? probe,
        ),
      );

  group('AddProfileScreen', () {
    testWidgets('renders mode selector and common fields with generic placeholders',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      expect(find.byKey(const Key('add_profile_mode_selector')), findsOneWidget);
      expect(find.byKey(const Key('add_profile_url_field')), findsOneWidget);
      expect(find.byKey(const Key('add_profile_token_field')), findsOneWidget);
      expect(find.byKey(const Key('add_profile_name_field')), findsOneWidget);

      final urlField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('add_profile_url_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(urlField.decoration?.hintText, 'https://hermes.example.com');

      final tokenField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('add_profile_token_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(tokenField.decoration?.hintText, 'device bridge token');

      expect(find.byKey(const Key('add_profile_url_helper')), findsOneWidget);
      expect(find.byKey(const Key('add_profile_model_field')), findsNothing);
      expect(find.byKey(const Key('add_profile_temperature_slider')), findsNothing);

      await tester.tap(find.text('OpenAI LLM'));
      await tester.pumpAndSettle();

      final openAiUrlField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('add_profile_url_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(openAiUrlField.decoration?.hintText, 'https://api.openai.com/v1');

      final openAiTokenField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('add_profile_token_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(openAiTokenField.decoration?.hintText, 'sk-...');
      expect(find.byKey(const Key('add_profile_url_helper')), findsNothing);
    });

    testWidgets('token field label depends on the selected mode',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      TextField tokenTextField() => tester.widget<TextField>(
            find.descendant(
              of: find.byKey(const Key('add_profile_token_field')),
              matching: find.byType(TextField),
            ),
          );

      expect(tokenTextField().decoration?.labelText, 'Device Token');

      await tester.tap(find.text('OpenAI LLM'));
      await tester.pumpAndSettle();

      expect(tokenTextField().decoration?.labelText, 'Auth Token / API Key');
    });

    testWidgets('shows model and temperature controls only in OpenAI mode',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.tap(find.text('OpenAI LLM'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_profile_model_field')), findsOneWidget);
      expect(find.byKey(const Key('add_profile_temperature_slider')), findsOneWidget);
      expect(find.byKey(const Key('add_profile_name_chip_Dev')), findsNothing);

      await tester.tap(find.text('Hermes Node'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('add_profile_model_field')), findsNothing);
      expect(find.byKey(const Key('add_profile_temperature_slider')), findsNothing);
      expect(find.byKey(const Key('add_profile_name_chip_Dev')), findsOneWidget);
    });

    testWidgets('name suggestion chip fills the profile name field', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.tap(find.byKey(const Key('add_profile_name_chip_Dev')));
      await tester.pump();

      final nameField = tester.widget<TextFormField>(
        find.byKey(const Key('add_profile_name_field')),
      );
      expect(nameField.controller?.text, 'Dev');
    });

    testWidgets(
        'Test Connection in Hermes mode shows the neutral notice without probing',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'https://hermes.example.com',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_token_field')),
        'secret-token',
      );

      await tester.ensureVisible(
        find.byKey(const Key('add_profile_test_connection_button')),
      );
      await tester.tap(
        find.byKey(const Key('add_profile_test_connection_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('add_profile_probe_notice')), findsOneWidget);
      expect(find.byKey(const Key('add_profile_probe_success')), findsNothing);
      expect(find.byKey(const Key('add_profile_probe_error')), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const Key('add_profile_probe_notice')),
          matching: find.text(
            'REST probe does not apply to Hermes Node profiles — the Gateway '
            'socket (/device/ws) is dialed when the profile is activated.',
          ),
        ),
        findsOneWidget,
      );
      verifyNever(() => probe.probeHermesNode(
            url: any(named: 'url'),
            token: any(named: 'token'),
          ));
      verifyNever(() => probe.probeOpenAi(
            url: any(named: 'url'),
            apiKey: any(named: 'apiKey'),
            model: any(named: 'model'),
          ));
    });

    testWidgets('Test Connection failure in OpenAI mode renders the red probe badge',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.tap(find.text('OpenAI LLM'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'https://api.openai.com/v1',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_token_field')),
        'sk-test',
      );
      when(() => probe.probeOpenAi(
            url: any(named: 'url'),
            apiKey: any(named: 'apiKey'),
            model: any(named: 'model'),
          )).thenAnswer(
        (_) async => const ProbeResult(
          isSuccess: false,
          message: 'Connection failed: HTTP 401',
        ),
      );

      await tester.ensureVisible(
        find.byKey(const Key('add_profile_test_connection_button')),
      );
      await tester.tap(
        find.byKey(const Key('add_profile_test_connection_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('add_profile_probe_error')), findsOneWidget);
      expect(find.textContaining('Connection failed: HTTP 401'), findsOneWidget);
    });

    testWidgets('Test Connection refuses to probe when URL or token is invalid',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'not a url',
      );
      await tester.ensureVisible(
        find.byKey(const Key('add_profile_test_connection_button')),
      );
      await tester.tap(
        find.byKey(const Key('add_profile_test_connection_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.byKey(const Key('add_profile_probe_error')), findsOneWidget);
      expect(find.textContaining('Fix URL and token first'), findsOneWidget);
      verifyNever(() => probe.probeHermesNode(
            url: any(named: 'url'),
            token: any(named: 'token'),
          ));
      verifyNever(() => probe.probeOpenAi(
            url: any(named: 'url'),
            apiKey: any(named: 'apiKey'),
            model: any(named: 'model'),
          ));
    });

    testWidgets('Test Connection in OpenAI mode calls probeOpenAi',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.tap(find.text('OpenAI LLM'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'https://api.openai.com/v1',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_token_field')),
        'sk-test',
      );
      when(() => probe.probeOpenAi(
            url: any(named: 'url'),
            apiKey: any(named: 'apiKey'),
            model: any(named: 'model'),
          )).thenAnswer(
        (_) async => const ProbeResult(isSuccess: true, message: 'OK (10ms)'),
      );

      await tester.ensureVisible(
        find.byKey(const Key('add_profile_test_connection_button')),
      );
      await tester.tap(
        find.byKey(const Key('add_profile_test_connection_button')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      verify(() => probe.probeOpenAi(
            url: any(named: 'url'),
            apiKey: any(named: 'apiKey'),
            model: any(named: 'model'),
          )).called(1);
      verifyNever(() => probe.probeHermesNode(
            url: any(named: 'url'),
            token: any(named: 'token'),
          ));
    });

    testWidgets(
        'Save Profile in Hermes mode forwards name/url/token with makeActive false',
        (tester) async {
      when(() => cubit.addProfile(
            name: any(named: 'name'),
            gatewayUrl: any(named: 'gatewayUrl'),
            token: any(named: 'token'),
            makeActive: any(named: 'makeActive'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
            kind: any(named: 'kind'),
          )).thenAnswer((_) async {});
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'https://hermes.example.com',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_token_field')),
        'secret-token',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_name_field')),
        'Ops',
      );
      await tester.ensureVisible(
        find.byKey(const Key('add_profile_submit_button')),
      );
      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pump();

      verify(() => cubit.addProfile(
            name: 'Ops',
            gatewayUrl: 'https://hermes.example.com',
            token: 'secret-token',
            makeActive: false,
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
            kind: any(named: 'kind'),
          )).called(1);
    });

    testWidgets('Save Profile in Hermes mode rejects a URL with a path',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'https://host/v1',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_token_field')),
        'secret-token',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_name_field')),
        'Ops',
      );
      await tester.ensureVisible(
        find.byKey(const Key('add_profile_submit_button')),
      );
      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pump();

      expect(
        find.text(
          'Leave the path empty — the app dials it verbatim instead of '
          '/device/ws (found "/v1")',
        ),
        findsOneWidget,
      );
      expect(find.textContaining('found "/v1"'), findsOneWidget);
      verifyNever(() => cubit.addProfile(
            name: any(named: 'name'),
            gatewayUrl: any(named: 'gatewayUrl'),
            token: any(named: 'token'),
            makeActive: any(named: 'makeActive'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
            kind: any(named: 'kind'),
          ));
    });

    testWidgets('Save Profile in Hermes mode accepts a pathless URL',
        (tester) async {
      when(() => cubit.addProfile(
            name: any(named: 'name'),
            gatewayUrl: any(named: 'gatewayUrl'),
            token: any(named: 'token'),
            makeActive: any(named: 'makeActive'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
            kind: any(named: 'kind'),
          )).thenAnswer((_) async {});
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'https://host',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_token_field')),
        'secret-token',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_name_field')),
        'Ops',
      );
      await tester.ensureVisible(
        find.byKey(const Key('add_profile_submit_button')),
      );
      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pump();

      verify(() => cubit.addProfile(
            name: 'Ops',
            gatewayUrl: 'https://host',
            token: 'secret-token',
            makeActive: false,
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
            kind: any(named: 'kind'),
          )).called(1);
    });

    testWidgets('Save Profile blocks submission when the form is invalid',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.ensureVisible(
        find.byKey(const Key('add_profile_submit_button')),
      );
      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pump();

      expect(
        find.text('Enter a valid HTTP/HTTPS/WS/WSS URL'),
        findsOneWidget,
      );
      expect(find.text('Token cannot be empty'), findsOneWidget);
      expect(find.text('Name cannot be empty'), findsOneWidget);
      verifyNever(() => cubit.addProfile(
            name: any(named: 'name'),
            gatewayUrl: any(named: 'gatewayUrl'),
            token: any(named: 'token'),
            makeActive: any(named: 'makeActive'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
            kind: any(named: 'kind'),
          ));
    });

    testWidgets('Save Profile in OpenAI mode forwards the entered model',
        (tester) async {
      when(() => cubit.addProfile(
            name: any(named: 'name'),
            gatewayUrl: any(named: 'gatewayUrl'),
            token: any(named: 'token'),
            makeActive: any(named: 'makeActive'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
            kind: any(named: 'kind'),
          )).thenAnswer((_) async {});
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.tap(find.text('OpenAI LLM'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'https://api.openai.com/v1',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_token_field')),
        'sk-test',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_name_field')),
        'OpenAI',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_model_field')),
        'gpt-4o-mini',
      );
      await tester.ensureVisible(
        find.byKey(const Key('add_profile_submit_button')),
      );
      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pump();

      final captured = verify(() => cubit.addProfile(
            name: 'OpenAI',
            gatewayUrl: 'https://api.openai.com/v1',
            token: 'sk-test',
            makeActive: false,
            model: 'gpt-4o-mini',
            temperature: captureAny(named: 'temperature'),
            kind: any(named: 'kind'),
          )).captured;
      expect(captured.single, isA<double>());
      expect(captured.single as double, inInclusiveRange(0.0, 1.0));
    });

    testWidgets('Save Profile in OpenAI mode forwards kind llmEndpoint',
        (tester) async {
      when(() => cubit.addProfile(
            name: any(named: 'name'),
            gatewayUrl: any(named: 'gatewayUrl'),
            token: any(named: 'token'),
            makeActive: any(named: 'makeActive'),
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
            kind: any(named: 'kind'),
          )).thenAnswer((_) async {});
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'https://hermes.example.com',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_token_field')),
        'secret-token',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_name_field')),
        'Hermes',
      );
      await tester.ensureVisible(
        find.byKey(const Key('add_profile_submit_button')),
      );
      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pump();

      verify(() => cubit.addProfile(
            name: 'Hermes',
            gatewayUrl: 'https://hermes.example.com',
            token: 'secret-token',
            makeActive: false,
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
            kind: ServerProfileKind.hermesAgent,
          )).called(1);

      await tester.tap(find.text('OpenAI LLM'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'https://api.openai.com/v1',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_token_field')),
        'sk-test',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_name_field')),
        'OpenAI',
      );
      await tester.ensureVisible(
        find.byKey(const Key('add_profile_submit_button')),
      );
      await tester.tap(find.byKey(const Key('add_profile_submit_button')));
      await tester.pump();

      verify(() => cubit.addProfile(
            name: 'OpenAI',
            gatewayUrl: 'https://api.openai.com/v1',
            token: 'sk-test',
            makeActive: false,
            model: any(named: 'model'),
            temperature: any(named: 'temperature'),
            kind: ServerProfileKind.llmEndpoint,
          )).called(1);
    });

    testWidgets(
        'shows an error SnackBar without popping when ServerProfileError is emitted',
        (tester) async {
      whenListen(
        cubit,
        Stream.fromIterable(const [
          ServerProfileLoaded(profiles: [], activeProfile: null),
          ServerProfileError(message: 'Failed to save server profile'),
        ]),
        initialState: const ServerProfileLoaded(
          profiles: [],
          activeProfile: null,
        ),
      );
      final router = GoRouter(
        initialLocation: '/settings/add-profile',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: SizedBox.shrink()),
          ),
          GoRoute(
            path: '/settings/add-profile',
            builder: (_, _) => AddProfileScreen(
              serverProfileCubit: cubit,
              probeService: probe,
            ),
          ),
        ],
      );

      await tester.pumpWidget(MaterialApp.router(
        theme: AppTheme.darkTheme,
        routerConfig: router,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Failed to save server profile'), findsOneWidget);
      expect(find.byType(AddProfileScreen), findsOneWidget);
    });
  });
}
