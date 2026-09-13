import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/presentation/screen/memory_vault/memory_vault_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget createWidgetUnderTest() {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: const MemoryVaultScreen(),
    );
  }

  group('MemoryVaultScreen', () {
    testWidgets('renders initial empty state with correct key and text', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('memory_empty_state')), findsOneWidget);
      expect(find.text('No memories saved yet. Tap + to add one.'), findsOneWidget);
      expect(find.byKey(const Key('memory_add_button')), findsOneWidget);
    });

    testWidgets('adding a memory record shows it in list', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('memory_add_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('memory_add_key_field')), 'work.role');
      await tester.enterText(find.byKey(const Key('memory_add_content_field')), 'Engineer');

      await tester.tap(find.byKey(const Key('memory_add_save_button')));
      await tester.pumpAndSettle();

      expect(find.text('work.role'), findsOneWidget);
      expect(find.text('Engineer'), findsOneWidget);
    });

    testWidgets('searching text filters memory items', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Add a test record first
      await tester.tap(find.byKey(const Key('memory_add_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('memory_add_key_field')), 'work.role');
      await tester.enterText(find.byKey(const Key('memory_add_content_field')), 'Engineer');
      await tester.tap(find.byKey(const Key('memory_add_save_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('memory_search_input')), 'work');
      await tester.pumpAndSettle();

      expect(find.text('work.role'), findsOneWidget);
      expect(find.text('Engineer'), findsOneWidget);
    });

    testWidgets('shows empty state when search finds no results', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Add a test record first
      await tester.tap(find.byKey(const Key('memory_add_button')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('memory_add_key_field')), 'work.role');
      await tester.enterText(find.byKey(const Key('memory_add_content_field')), 'Engineer');
      await tester.tap(find.byKey(const Key('memory_add_save_button')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('memory_search_input')), 'unknown_query_123');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('memory_search_empty_state')), findsOneWidget);
      expect(find.text('No memory records match your search query'), findsOneWidget);
    });
  });
}
