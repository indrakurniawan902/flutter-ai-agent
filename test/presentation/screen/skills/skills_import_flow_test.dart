import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill_import_preview.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill_scan.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/skills_hub_screen.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

import '../../../helpers/mocks.dart';

void main() {
  const bundledSkill = Skill(
    id: 'task_planner',
    name: 'task_planner',
    description: 'Decomposes complex goals into steps',
    category: 'Productivity',
    tier: 'Tier 1 Auto',
    version: 'v1.2.0',
    tools: ['clipboard_read'],
    prompts: ['Plan tasks'],
    instructions: 'Break down goals.',
  );

  const importedSkill = Skill(
    id: 'community_weather',
    name: 'community_weather',
    description: 'Community weather skill',
    category: 'Productivity',
    tier: 'Tier 1 Auto',
    version: '1.0.0',
    tools: ['clipboard_read'],
    prompts: ['What is the weather'],
    instructions: 'Report weather.',
    isCommunity: true,
  );

  const cleanScan = SkillScanResult();
  const rejectedScan = SkillScanResult(unknownTools: ['shell_exec']);
  const advisoryScan = SkillScanResult(
    findings: [
      SkillScanFinding(
        patternId: 'ignore_previous_instructions',
        description: 'x',
        severity: SkillScanSeverity.critical,
      ),
    ],
  );

  SkillImportPreview cleanPreview() {
    return const SkillImportPreview(
      sourceUrl: 'https://example.com/SKILL.md',
      skill: importedSkill,
      rawMarkdown: '---\nname: x\n---\n',
      scan: cleanScan,
    );
  }

  SkillImportPreview rejectedPreview() {
    return const SkillImportPreview(
      sourceUrl: 'https://example.com/SKILL.md',
      skill: importedSkill,
      rawMarkdown: '---\nname: x\n---\n',
      scan: rejectedScan,
    );
  }

  SkillImportPreview advisoryPreview() {
    return const SkillImportPreview(
      sourceUrl: 'https://example.com/SKILL.md',
      skill: importedSkill,
      rawMarkdown: '---\nname: x\n---\n',
      scan: advisoryScan,
    );
  }

  setUpAll(() {
    registerFallbackValue('fallback');
    registerFallbackValue(cleanPreview());
    registerFallbackValue(bundledSkill);
  });

  late SkillsRegistryService registry;
  late MockSkillImportService mockImport;
  late SkillsCubit cubit;

  setUp(() {
    registry = SkillsRegistryService(loadDefaults: false);
    registry.registerSkill(bundledSkill);
    mockImport = MockSkillImportService();
    cubit = SkillsCubit(
      skillsRegistryService: registry,
      skillImportService: mockImport,
    );
  });

  tearDown(() {
    cubit.close();
  });

  Widget createWidget() {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: SkillsHubScreen(cubit: cubit),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(createWidget());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('skills_import_button')));
    await tester.pumpAndSettle();
  }

  Future<void> fetchUrl(WidgetTester tester, String url) async {
    await tester.enterText(
      find.byKey(const Key('skill_import_url_field')),
      url,
    );
    await tester.tap(find.byKey(const Key('skill_import_fetch_button')));
    await tester.pumpAndSettle();
  }

  testWidgets('import button opens dialog with url field', (tester) async {
    await openDialog(tester);

    expect(find.byKey(const Key('skill_import_dialog')), findsOneWidget);
    expect(find.byKey(const Key('skill_import_url_field')), findsOneWidget);
    expect(find.byKey(const Key('skill_import_fetch_button')), findsOneWidget);
  });

  testWidgets('clean preview shows details and enabled import', (tester) async {
    when(
      () => mockImport.buildPreview(any()),
    ).thenAnswer((_) async => Right(cleanPreview()));

    await openDialog(tester);
    await fetchUrl(tester, 'https://example.com/SKILL.md');

    expect(find.byKey(const Key('skill_import_preview')), findsOneWidget);
    final nameWidget = tester.widget<Text>(
      find.byKey(const Key('skill_import_preview_name')),
    );
    expect(nameWidget.data, importedSkill.name);
    expect(find.textContaining('Requested tools:'), findsOneWidget);
    expect(find.textContaining('Estimated prompt size: ~'), findsOneWidget);
    expect(find.text('No obvious injection patterns detected'), findsOneWidget);
    expect(find.textContaining('PASSED'), findsNothing);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('skill_import_confirm_button')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('confirm import registers skill and closes dialog', (
    tester,
  ) async {
    when(
      () => mockImport.buildPreview(any()),
    ).thenAnswer((_) async => Right(cleanPreview()));
    when(() => mockImport.confirmImport(any())).thenAnswer((inv) async {
      final p = inv.positionalArguments.first as SkillImportPreview;
      registry.registerSkill(p.skill);
      return Right(p.skill);
    });

    await openDialog(tester);
    await fetchUrl(tester, 'https://example.com/SKILL.md');

    await tester.tap(find.byKey(const Key('skill_import_confirm_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('skill_import_dialog')), findsNothing);
    expect(
      find.byKey(const Key('skill_card_community_weather')),
      findsOneWidget,
    );
    expect(find.text('COMMUNITY'), findsWidgets);
  });

  testWidgets('rejected preview disables import and shows unknown tools', (
    tester,
  ) async {
    when(
      () => mockImport.buildPreview(any()),
    ).thenAnswer((_) async => Right(rejectedPreview()));

    await openDialog(tester);
    await fetchUrl(tester, 'https://example.com/SKILL.md');

    final verdict = tester.widget<Text>(
      find.byKey(const Key('skill_import_scan_verdict')),
    );
    expect(
      verdict.data,
      contains('SECURITY: requests tools not in this build: shell_exec'),
    );
    expect(find.textContaining('PASSED'), findsNothing);
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('skill_import_confirm_button')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('advisory findings keep import enabled', (tester) async {
    when(
      () => mockImport.buildPreview(any()),
    ).thenAnswer((_) async => Right(advisoryPreview()));

    await openDialog(tester);
    await fetchUrl(tester, 'https://example.com/SKILL.md');

    final verdict = tester.widget<Text>(
      find.byKey(const Key('skill_import_scan_verdict')),
    );
    expect(
      verdict.data,
      contains(
        'Possible injection patterns (advisory): ignore_previous_instructions',
      ),
    );
    expect(
      tester
          .widget<TextButton>(
            find.byKey(const Key('skill_import_confirm_button')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('fetch failure surfaces error message', (tester) async {
    when(
      () => mockImport.buildPreview(any()),
    ).thenAnswer((_) async => const Left(NetworkFailure('boom')));

    await openDialog(tester);
    await fetchUrl(tester, 'https://example.com/SKILL.md');

    expect(find.byKey(const Key('skill_import_error')), findsOneWidget);
    expect(find.textContaining('boom'), findsOneWidget);
  });

  testWidgets('import preview does not overflow at 320x568', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    when(
      () => mockImport.buildPreview(any()),
    ).thenAnswer((_) async => Right(cleanPreview()));

    await openDialog(tester);
    await fetchUrl(tester, 'https://example.com/SKILL.md');

    expect(find.byKey(const Key('skill_import_preview')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
