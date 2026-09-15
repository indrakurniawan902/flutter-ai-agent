import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/nfc_tag_prompt_binding.dart';
import 'package:flutter_ai_agent/domain/services/tools/nfc_prompt_resolver.dart';
import 'package:flutter_ai_agent/domain/tools/device/nfc_service.dart';
import 'package:flutter_ai_agent/presentation/screen/server_profiles/cubit/server_profile_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/cubit/settings_state.dart';
import 'package:flutter_ai_agent/presentation/screen/settings/settings_screen.dart';
import 'package:flutter_ai_agent/utils/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

class _MockNfcService extends Mock implements NfcServiceBase {}

class _MockSecureStorageService extends Mock implements SecureStorageService {}

void main() {
  late MockSettingsCubit mockSettingsCubit;
  late MockServerProfileCubit mockServerProfileCubit;

  const loadedBase = SettingsLoaded(
    baseUrl: 'https://example.com/v1',
    apiKey: 'sk-key',
    model: 'ag-glm',
    temperature: 0.7,
    nfcAvailable: true,
  );

  final binding = NfcTagPromptBinding(
    cardUid: '04a2b3c4d5',
    prompt: 'Open the gate',
    label: 'Gate Opener',
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    mockSettingsCubit = MockSettingsCubit();
    mockServerProfileCubit = MockServerProfileCubit();
    when(() => mockServerProfileCubit.state).thenReturn(
      const ServerProfileLoaded(profiles: [], activeProfile: null),
    );
  });

  Widget buildWidget() {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: SettingsScreen(
        cubit: mockSettingsCubit,
        serverProfileCubit: mockServerProfileCubit,
      ),
    );
  }

  group('NFC section rendering', () {
    testWidgets('renders NFC section with 0 bindings and Add button works',
        (tester) async {
      whenListen(mockSettingsCubit, Stream<SettingsState>.empty(),
          initialState: loadedBase);
      when(() => mockSettingsCubit.scanAndBindNfcTag())
          .thenAnswer((_) async {});

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('No NFC triggers yet'), findsOneWidget);
      expect(find.byKey(const Key('nfc_add_trigger_button')), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('nfc_add_trigger_button')));
      await tester.tap(find.byKey(const Key('nfc_add_trigger_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Tap the NFC tag to the back of your phone…'),
          findsOneWidget);
      verify(() => mockSettingsCubit.scanAndBindNfcTag()).called(1);
    });

    testWidgets('Add NFC Trigger is disabled when NFC is unavailable',
        (tester) async {
      whenListen(
        mockSettingsCubit,
        Stream<SettingsState>.empty(),
        initialState: const SettingsLoaded(
          baseUrl: 'https://example.com/v1',
          apiKey: 'sk-key',
          model: 'ag-glm',
          temperature: 0.7,
        ),
      );

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      final button = tester.widget<OutlinedButton>(
        find.byKey(const Key('nfc_add_trigger_button')),
      );
      expect(button.onPressed, isNull);
    });
  });

  group('NFC scan and bind flow', () {
    testWidgets('scan result shows form, save calls confirmNfcPromptBinding',
        (tester) async {
      final controller = StreamController<SettingsState>();
      whenListen(mockSettingsCubit, controller.stream,
          initialState: loadedBase);
      when(() => mockSettingsCubit.scanAndBindNfcTag())
          .thenAnswer((_) async {});
      when(() => mockSettingsCubit.confirmNfcPromptBinding(
            any(),
            any(),
            label: any(named: 'label'),
          )).thenAnswer((_) async {});

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('nfc_add_trigger_button')));
      await tester.tap(find.byKey(const Key('nfc_add_trigger_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      controller.add(const SettingsNfcScanResult(uid: '04A2B3C4D5'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nfc_prompt_field')), findsOneWidget);
      expect(find.byKey(const Key('nfc_label_field')), findsOneWidget);

      await tester.enterText(
          find.byKey(const Key('nfc_prompt_field')), 'Open the gate');
      await tester.enterText(
          find.byKey(const Key('nfc_label_field')), 'Gate Opener');
      await tester.pump();

      await tester.tap(find.byKey(const Key('nfc_save_button')));
      await tester.pumpAndSettle();

      verify(() => mockSettingsCubit.confirmNfcPromptBinding(
            '04A2B3C4D5',
            'Open the gate',
            label: 'Gate Opener',
          )).called(1);

      controller.add(SettingsLoaded(
        baseUrl: 'https://example.com/v1',
        apiKey: 'sk-key',
        model: 'ag-glm',
        temperature: 0.7,
        nfcAvailable: true,
        nfcPromptBindings: [binding],
      ));
      await tester.pumpAndSettle();
      expect(find.text('Gate Opener'), findsOneWidget);

      await controller.close();
    });

    testWidgets('scan failure shows error with Retry and Cancel',
        (tester) async {
      final controller = StreamController<SettingsState>();
      whenListen(mockSettingsCubit, controller.stream,
          initialState: loadedBase);
      when(() => mockSettingsCubit.scanAndBindNfcTag())
          .thenAnswer((_) async {});

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      await tester.ensureVisible(find.byKey(const Key('nfc_add_trigger_button')));
      await tester.tap(find.byKey(const Key('nfc_add_trigger_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      controller.add(const SettingsError(message: 'NFC scan timed out'));
      await tester.pumpAndSettle();

      expect(find.text('NFC scan timed out'), findsNWidgets(2));
      expect(find.byKey(const Key('nfc_retry_button')), findsOneWidget);

      await tester.tap(find.byKey(const Key('nfc_cancel_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nfc_retry_button')), findsNothing);

      await controller.close();
    });
  });

  group('NFC delete flow', () {
    testWidgets('delete binding shows confirmation and calls remove',
        (tester) async {
      whenListen(
        mockSettingsCubit,
        Stream<SettingsState>.empty(),
        initialState: SettingsLoaded(
          baseUrl: 'https://example.com/v1',
          apiKey: 'sk-key',
          model: 'ag-glm',
          temperature: 0.7,
          nfcAvailable: true,
          nfcPromptBindings: [binding],
        ),
      );
      when(() => mockSettingsCubit.removeNfcPromptBinding(any()))
          .thenAnswer((_) async {});

      await tester.pumpWidget(buildWidget());
      await tester.pump();

      expect(find.text('Gate Opener'), findsOneWidget);

      await tester.ensureVisible(
          find.byKey(const Key('nfc_delete_04a2b3c4d5')));
      await tester.tap(find.byKey(const Key('nfc_delete_04a2b3c4d5')));
      await tester.pumpAndSettle();

      expect(find.text('Delete NFC Trigger'), findsOneWidget);

      await tester.tap(find.byKey(const Key('nfc_confirm_delete_button')));
      await tester.pumpAndSettle();

      verify(() => mockSettingsCubit.removeNfcPromptBinding('04a2b3c4d5'))
          .called(1);
    });
  });

  group('NfcPromptResolver', () {
    test('returns prompt for known UID', () {
      final resolver = NfcPromptResolver(bindings: [binding]);

      expect(resolver.resolve('04A2B3C4D5'), 'Open the gate');
      expect(resolver.resolve('  04a2b3c4d5  '), 'Open the gate');
    });

    test('returns null for unknown UID', () {
      final resolver = NfcPromptResolver(bindings: [binding]);

      expect(resolver.resolve('ffffffff'), isNull);
      expect(resolver.resolve(''), isNull);
    });
  });

  group('SettingsCubit NFC scan and binding methods', () {
    late _MockNfcService mockNfc;
    late _MockSecureStorageService mockStorage;

    setUpAll(() {
      registerFallbackValue(<NfcTagPromptBinding>[]);
    });

    setUp(() {
      mockNfc = _MockNfcService();
      mockStorage = _MockSecureStorageService();
      when(() => mockStorage.saveNfcPromptBindings(any()))
          .thenAnswer((_) async {});
    });

    test('scanAndBindNfcTag emits SettingsError when NFC is unavailable', () async {
      when(() => mockNfc.isAvailable())
          .thenAnswer((_) async => const Right(false));

      final cubit = SettingsCubit(
        secureStorageService: mockStorage,
        nfcService: mockNfc,
        autoLoad: false,
      );
      cubit.emit(loadedBase);

      await cubit.scanAndBindNfcTag();

      expect(cubit.state, isA<SettingsError>());
      final error = cubit.state as SettingsError;
      expect(error.message, contains('not supported'));
      expect(error.baseUrl, loadedBase.baseUrl);
      expect(error.apiKey, loadedBase.apiKey);
      expect(error.model, loadedBase.model);
    });

    test('scanAndBindNfcTag emits SettingsError when NFC is disabled', () async {
      when(() => mockNfc.isAvailable())
          .thenAnswer((_) async => const Right(true));
      when(() => mockNfc.isEnabled())
          .thenAnswer((_) async => const Right(false));

      final cubit = SettingsCubit(
        secureStorageService: mockStorage,
        nfcService: mockNfc,
        autoLoad: false,
      );
      cubit.emit(loadedBase);

      await cubit.scanAndBindNfcTag();

      expect(cubit.state, isA<SettingsError>());
      final error = cubit.state as SettingsError;
      expect(error.message, contains('disabled'));
      expect(error.baseUrl, loadedBase.baseUrl);
      expect(error.apiKey, loadedBase.apiKey);
    });

    test('scanAndBindNfcTag emits SettingsNfcScanResult preserving settings fields', () async {
      when(() => mockNfc.isAvailable())
          .thenAnswer((_) async => const Right(true));
      when(() => mockNfc.isEnabled())
          .thenAnswer((_) async => const Right(true));
      when(() => mockNfc.readCardUid())
          .thenAnswer((_) async => const Right('04A2B3C4D5'));

      final cubit = SettingsCubit(
        secureStorageService: mockStorage,
        nfcService: mockNfc,
        autoLoad: false,
      );
      cubit.emit(loadedBase.copyWith(nfcPromptBindings: [binding]));

      await cubit.scanAndBindNfcTag();

      expect(cubit.state, isA<SettingsNfcScanResult>());
      final scanResult = cubit.state as SettingsNfcScanResult;
      expect(scanResult.uid, '04A2B3C4D5');
      expect(scanResult.baseUrl, loadedBase.baseUrl);
      expect(scanResult.apiKey, loadedBase.apiKey);
      expect(scanResult.model, loadedBase.model);
      expect(scanResult.nfcPromptBindings, [binding]);
      expect(scanResult.nfcAvailable, isTrue);
    });

    test('confirmNfcPromptBinding preserves existing bindings and settings fields', () async {
      final cubit = SettingsCubit(
        secureStorageService: mockStorage,
        nfcService: mockNfc,
        autoLoad: false,
      );
      cubit.emit(SettingsNfcScanResult(
        uid: '11223344',
        baseUrl: loadedBase.baseUrl,
        apiKey: loadedBase.apiKey,
        model: loadedBase.model,
        temperature: loadedBase.temperature,
        progressiveToolPruning: loadedBase.progressiveToolPruning,
        nfcPromptBindings: [binding],
        nfcAvailable: true,
      ));

      await cubit.confirmNfcPromptBinding('11223344', 'Second trigger', label: 'Second');

      expect(cubit.state, isA<SettingsLoaded>());
      final loaded = cubit.state as SettingsLoaded;
      expect(loaded.baseUrl, loadedBase.baseUrl);
      expect(loaded.apiKey, loadedBase.apiKey);
      expect(loaded.nfcPromptBindings.length, 2);
      expect(loaded.nfcPromptBindings[0].cardUid, binding.cardUid);
      expect(loaded.nfcPromptBindings[1].cardUid, '11223344');
      expect(loaded.nfcPromptBindings[1].prompt, 'Second trigger');
      expect(loaded.nfcPromptBindings[1].label, 'Second');
    });
  });
}
