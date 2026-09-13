import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/domain/entities/server_profiles/server_profile.dart';
import 'package:flutter_ai_agent/domain/services/settings/server_profile_probe_service.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/add_profile_screen.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockServerProfileCubit extends MockCubit<ServerProfileState>
    implements ServerProfileCubit {}

class MockProbeService extends Mock implements ServerProfileProbeService {}

void main() {
  late MockServerProfileCubit cubit;
  late MockProbeService probe;

  setUpAll(() {
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
      expect(urlField.decoration?.hintText, 'https://hermes.example.com/v1');

      final tokenField = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(const Key('add_profile_token_field')),
          matching: find.byType(TextField),
        ),
      );
      expect(tokenField.decoration?.hintText, 'sk-...');

      expect(find.byKey(const Key('add_profile_model_field')), findsNothing);
      expect(find.byKey(const Key('add_profile_temperature_slider')), findsNothing);
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

    testWidgets('Test Connection success renders the green probe badge and calls probeHermesNode',
        (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pump();

      await tester.enterText(
        find.byKey(const Key('add_profile_url_field')),
        'https://hermes.example.com/v1',
      );
      await tester.enterText(
        find.byKey(const Key('add_profile_token_field')),
        'secret-token',
      );

      when(() => probe.probeHermesNode(
            url: 'https://hermes.example.com/v1',
            token: 'secret-token',
          )).thenAnswer(
        (_) async => const ProbeResult(
          isSuccess: true,
          message: 'Connected (42ms) • 2 models',
          latencyMs: 42,
          models: ['a', 'b'],
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

      expect(find.byKey(const Key('add_profile_probe_success')), findsOneWidget);
      expect(find.textContaining('Connected (42ms)'), findsOneWidget);
      verify(() => probe.probeHermesNode(
            url: 'https://hermes.example.com/v1',
            token: 'secret-token',
          )).called(1);
    });
  });
}
