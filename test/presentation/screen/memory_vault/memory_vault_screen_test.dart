import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/theme/hermes_theme.dart';
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
    testWidgets('renders search field, FTS5 badge, and memory records', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.text('Memory Vault'), findsOneWidget);
      expect(find.byKey(const Key('memory_search_input')), findsOneWidget);
      expect(find.byKey(const Key('memory_fts5_badge')), findsOneWidget);
      expect(find.textContaining('FTS5 Indexed'), findsOneWidget);
    });

    testWidgets('searching text filters memory items', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      expect(find.textContaining('Eryushin'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('memory_search_input')), 'router');
      await tester.pumpAndSettle();

      expect(find.textContaining('9router'), findsOneWidget);
      expect(find.textContaining('SM-G991B'), findsNothing);
    });

    testWidgets('shows empty state when search finds no results', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('memory_search_input')), 'unknown_query_123');
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('memory_empty_state')), findsOneWidget);
      expect(find.text('No memory records match your search query'), findsOneWidget);
    });
  });
}
