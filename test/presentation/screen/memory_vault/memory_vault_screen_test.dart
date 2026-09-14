import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/failure.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/chat/memory_item.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/presentation/screen/memory_vault/memory_vault_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import '../../../helpers/mocks.dart';

void main() {
  Widget createWidgetUnderTest() {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: const MemoryVaultScreen(),
    );
  }

  MemoryItem item({
    int id = 1,
    String key = 'service.key',
    String content = 'service content',
    List<String> tags = const [],
  }) {
    final now = DateTime(2026, 9, 11, 15, 20);
    return MemoryItem(
      id: id,
      key: key,
      content: content,
      tags: tags,
      createdAt: now,
      updatedAt: now,
    );
  }

  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  tearDown(() async {
    await sl.reset();
  });

  group('MemoryVaultScreen', () {
    testWidgets('renders search field, FTS5 badge, and memory records', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Memory Vault'), findsOneWidget);
      expect(find.byKey(const Key('memory_search_input')), findsOneWidget);
      expect(find.byKey(const Key('memory_fts5_badge')), findsOneWidget);
      expect(find.textContaining('FTS5 Indexed'), findsOneWidget);
    });

    testWidgets('empty vault renders the never-saved empty state', (
      tester,
    ) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('memory_empty_state')), findsOneWidget);
      expect(
        find.text('No memories saved yet. Tap + to add one.'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('searching text filters memory items', (tester) async {
      final mockMemory = MockLocalMemoryService();
      when(
        () => mockMemory.getAllMemories(limit: any(named: 'limit')),
      ).thenAnswer(
        (_) async => Right([
          item(id: 1, key: 'work.role', content: 'Engineer'),
          item(id: 2, key: 'home.city', content: 'Bandung'),
        ]),
      );
      when(() => mockMemory.searchMemories('work', 50)).thenAnswer(
        (_) async =>
            Right([item(id: 1, key: 'work.role', content: 'Engineer')]),
      );
      sl.registerFactory<LocalMemoryServiceBase>(() => mockMemory);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Engineer'), findsOneWidget);
      expect(find.text('Bandung'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('memory_search_input')),
        'work',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.text('Engineer'), findsOneWidget);
      expect(find.text('Bandung'), findsNothing);
    });

    testWidgets('shows search empty state when the query matches nothing', (
      tester,
    ) async {
      final mockMemory = MockLocalMemoryService();
      when(
        () => mockMemory.getAllMemories(limit: any(named: 'limit')),
      ).thenAnswer((_) async => Right([item()]));
      when(
        () => mockMemory.searchMemories('unknown_query_123', 50),
      ).thenAnswer((_) async => const Right([]));
      sl.registerFactory<LocalMemoryServiceBase>(() => mockMemory);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('memory_search_input')),
        'unknown_query_123',
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('memory_search_empty_state')),
        findsOneWidget,
      );
      expect(
        find.text('No memory records match your search query'),
        findsOneWidget,
      );
    });

    testWidgets(
      'FAB opens Create Memory sheet and Save no-ops when service not registered',
      (tester) async {
        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('memory_create_fab')));
        await tester.pumpAndSettle();

        expect(find.text('Create Memory'), findsOneWidget);
        expect(find.byKey(const Key('memory_form_key_field')), findsOneWidget);
        expect(
          find.byKey(const Key('memory_form_content_field')),
          findsOneWidget,
        );
        expect(
          find.byKey(const Key('memory_form_category_field')),
          findsOneWidget,
        );
        expect(find.byKey(const Key('memory_form_tags_field')), findsOneWidget);

        final saveButton = find.byKey(const Key('memory_form_save_button'));
        expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

        await tester.enterText(
          find.byKey(const Key('memory_form_key_field')),
          'test.key',
        );
        await tester.enterText(
          find.byKey(const Key('memory_form_content_field')),
          'test content',
        );
        await tester.pump();

        final enabledSaveButton = tester.widget<FilledButton>(saveButton);
        expect(enabledSaveButton.onPressed, isNotNull);

        await tester.tap(saveButton);
        await tester.pump();
        await tester.pumpAndSettle();

        expect(find.text('Create Memory'), findsNothing);
      },
    );

    testWidgets(
      'tapping a memory item opens Edit Memory sheet prefilled with disabled key',
      (tester) async {
        final mockMemory = MockLocalMemoryService();
        when(
          () => mockMemory.getAllMemories(limit: any(named: 'limit')),
        ).thenAnswer(
          (_) async =>
              Right([item(id: 1, key: 'work.role', content: 'Engineer')]),
        );
        sl.registerFactory<LocalMemoryServiceBase>(() => mockMemory);

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('memory_item_1')));
        await tester.pumpAndSettle();

        expect(find.text('Edit Memory'), findsOneWidget);
        final keyField = tester.widget<TextField>(
          find.byKey(const Key('memory_form_key_field')),
        );
        expect(keyField.controller!.text, 'work.role');
        expect(keyField.enabled, isFalse);
        expect(find.text('Key cannot be changed'), findsOneWidget);
        final contentField = tester.widget<TextField>(
          find.byKey(const Key('memory_form_content_field')),
        );
        expect(contentField.controller!.text, contains('Engineer'));
      },
    );

    testWidgets('delete button opens confirmation dialog, Cancel keeps item', (
      tester,
    ) async {
      final mockMemory = MockLocalMemoryService();
      when(
        () => mockMemory.getAllMemories(limit: any(named: 'limit')),
      ).thenAnswer(
        (_) async =>
            Right([item(id: 1, key: 'work.role', content: 'Engineer')]),
      );
      sl.registerFactory<LocalMemoryServiceBase>(() => mockMemory);

      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('memory_delete_confirm_dialog')),
        findsOneWidget,
      );
      expect(find.text('Delete this memory permanently?'), findsOneWidget);

      await tester.tap(find.byKey(const Key('memory_delete_cancel_button')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('memory_delete_confirm_dialog')),
        findsNothing,
      );
      expect(find.text('work.role'), findsOneWidget);
    });

    testWidgets(
      'delete confirm closes dialog with graceful no-op when service not registered',
      (tester) async {
        final mockMemory = MockLocalMemoryService();
        when(
          () => mockMemory.getAllMemories(limit: any(named: 'limit')),
        ).thenAnswer(
          (_) async =>
              Right([item(id: 1, key: 'work.role', content: 'Engineer')]),
        );
        sl.registerFactory<LocalMemoryServiceBase>(() => mockMemory);

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        // Drop the service after the list hydrated: the confirm path must still
        // close cleanly instead of throwing on a missing registration.
        await sl.reset();

        await tester.tap(find.byIcon(Icons.delete_outline).first);
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('memory_delete_confirm_dialog')),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('memory_delete_confirm_button')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('memory_delete_confirm_dialog')),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    group('service-backed', () {
      late MockLocalMemoryService mockMemory;

      setUp(() {
        mockMemory = MockLocalMemoryService();
        when(
          () => mockMemory.getAllMemories(limit: any(named: 'limit')),
        ).thenAnswer((_) async => Right([item()]));
        sl.registerFactory<LocalMemoryServiceBase>(() => mockMemory);
      });

      testWidgets('renders service results as-is for tag-only FTS matches', (
        tester,
      ) async {
        when(() => mockMemory.searchMemories('tagtoken', 50)).thenAnswer(
          (_) async => Right([
            item(
              id: 7,
              key: 'note.one',
              content: 'body without the token',
              tags: const ['tagtoken'],
            ),
          ]),
        );

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('memory_search_input')),
          'tagtoken',
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pumpAndSettle();

        expect(find.text('body without the token'), findsOneWidget);
        expect(find.byKey(const Key('memory_item_7')), findsOneWidget);
      });

      testWidgets(
        'drops stale search responses that land after a newer query',
        (tester) async {
          final firstResponse = Completer<Either<Failure, List<MemoryItem>>>();
          when(
            () => mockMemory.searchMemories('first', 50),
          ).thenAnswer((_) => firstResponse.future);
          when(() => mockMemory.searchMemories('second', 50)).thenAnswer(
            (_) async =>
                Right([item(id: 2, key: 'fresh.key', content: 'fresh result')]),
          );

          await tester.pumpWidget(createWidgetUnderTest());
          await tester.pumpAndSettle();

          await tester.enterText(
            find.byKey(const Key('memory_search_input')),
            'first',
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          await tester.enterText(
            find.byKey(const Key('memory_search_input')),
            'second',
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await tester.pumpAndSettle();

          expect(find.text('fresh result'), findsOneWidget);

          firstResponse.complete(
            Right([item(id: 3, key: 'stale.key', content: 'stale result')]),
          );
          await tester.pumpAndSettle();

          expect(find.text('stale result'), findsNothing);
          expect(find.text('fresh result'), findsOneWidget);
        },
      );

      testWidgets('successful save closes sheet and reports success', (
        tester,
      ) async {
        when(
          () => mockMemory.saveMemory(any(), any(), any()),
        ).thenAnswer((_) async => Right(item()));

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const Key('memory_create_fab')));
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byKey(const Key('memory_form_key_field')),
          'new.key',
        );
        await tester.enterText(
          find.byKey(const Key('memory_form_content_field')),
          'new content',
        );
        await tester.pump();

        await tester.tap(find.byKey(const Key('memory_form_save_button')));
        await tester.pumpAndSettle();

        expect(find.text('Create Memory'), findsNothing);
        expect(find.text('Memory saved'), findsOneWidget);
      });

      testWidgets(
        'failed save (Left) keeps sheet open and shows failure message',
        (tester) async {
          when(
            () => mockMemory.saveMemory(any(), any(), any()),
          ).thenAnswer((_) async => const Left(CacheFailure('disk full')));

          await tester.pumpWidget(createWidgetUnderTest());
          await tester.pumpAndSettle();

          await tester.tap(find.byKey(const Key('memory_create_fab')));
          await tester.pumpAndSettle();

          await tester.enterText(
            find.byKey(const Key('memory_form_key_field')),
            'new.key',
          );
          await tester.enterText(
            find.byKey(const Key('memory_form_content_field')),
            'new content',
          );
          await tester.pump();

          await tester.tap(find.byKey(const Key('memory_form_save_button')));
          await tester.pumpAndSettle();

          expect(find.text('Create Memory'), findsOneWidget);
          expect(find.text('disk full'), findsOneWidget);
          expect(find.text('Memory saved'), findsNothing);
        },
      );

      testWidgets('successful delete reports deleted', (tester) async {
        when(
          () => mockMemory.deleteMemory(1),
        ).thenAnswer((_) async => const Right(true));

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.delete_outline).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('memory_delete_confirm_button')));
        await tester.pumpAndSettle();

        expect(find.textContaining('deleted.'), findsOneWidget);
      });

      testWidgets('failed delete (Left) surfaces failure, not success', (
        tester,
      ) async {
        when(
          () => mockMemory.deleteMemory(1),
        ).thenAnswer((_) async => const Left(CacheFailure('locked')));

        await tester.pumpWidget(createWidgetUnderTest());
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.delete_outline).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('memory_delete_confirm_button')));
        await tester.pumpAndSettle();

        expect(find.text('locked'), findsOneWidget);
        expect(find.textContaining('deleted.'), findsNothing);
      });
    });
  });
}
