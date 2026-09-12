import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/reasoning_card.dart';

void main() {
  Widget buildTestableWidget(Widget child) {
    return MaterialApp(
      theme: HermesTheme.darkTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ),
      ),
    );
  }

  const sampleThought =
      'Step 1: analyze user intent.\nStep 2: select tool.\nStep 3: execute.';

  bool containsEmoji(String text) {
    final emojiPattern = RegExp(
      '[\u{1F600}-\u{1F64F}\u{1F300}-\u{1F5FF}\u{1F680}-\u{1F6FF}'
      '\u{2600}-\u{26FF}\u{2700}-\u{27BF}\u{FE00}-\u{FE0F}'
      '\u{1F900}-\u{1F9FF}\u{1FA70}-\u{1FAFF}\u{2190}-\u{21FF}\u{2B00}-\u{2BFF}]',
      unicode: true,
    );
    return emojiPattern.hasMatch(text);
  }

  group('ReasoningCard Widget', () {
    testWidgets(
      'renders header with icon, Thought Process title, and chevron',
      (tester) async {
        // Arrange
        const card = ReasoningCard(thoughtProcess: sampleThought);

        // Act
        await tester.pumpWidget(buildTestableWidget(card));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text('Thought Process'), findsOneWidget);
        expect(find.byIcon(Icons.psychology_outlined), findsOneWidget);
        expect(find.byIcon(Icons.expand_more), findsOneWidget);
        expect(find.byKey(const Key('reasoning_card_header')), findsOneWidget);
      },
    );

    testWidgets('default state is collapsed: reasoning text is hidden',
        (tester) async {
      // Arrange
      const card = ReasoningCard(thoughtProcess: sampleThought);

      // Act
      await tester.pumpWidget(buildTestableWidget(card));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(sampleThought), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsNothing);
    });

    testWidgets(
      'tapping header expands the card with monospace styled trace',
      (tester) async {
        // Arrange
        const card = ReasoningCard(thoughtProcess: sampleThought);
        await tester.pumpWidget(buildTestableWidget(card));
        await tester.pumpAndSettle();

        // Act
        await tester.tap(find.byKey(const Key('reasoning_card_header')));
        await tester.pumpAndSettle();

        // Assert
        expect(find.text(sampleThought), findsOneWidget);
        expect(find.byIcon(Icons.expand_less), findsOneWidget);

        final textWidget = tester.widget<Text>(
          find.text(sampleThought),
        );
        expect(textWidget.style?.fontFamily, equals('monospace'));
        expect(textWidget.style?.fontSize, equals(12));
        expect(textWidget.style?.height, equals(1.4));
      },
    );

    testWidgets('tapping header again collapses the card', (tester) async {
      // Arrange
      const card = ReasoningCard(thoughtProcess: sampleThought);
      await tester.pumpWidget(buildTestableWidget(card));
      await tester.pumpAndSettle();

      // Act: expand then collapse
      await tester.tap(find.byKey(const Key('reasoning_card_header')));
      await tester.pumpAndSettle();
      expect(find.text(sampleThought), findsOneWidget);

      await tester.tap(find.byKey(const Key('reasoning_card_header')));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(sampleThought), findsNothing);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('respects initiallyExpanded true: trace initially visible',
        (tester) async {
      // Arrange
      const card = ReasoningCard(
        thoughtProcess: sampleThought,
        initiallyExpanded: true,
      );

      // Act
      await tester.pumpWidget(buildTestableWidget(card));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(sampleThought), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
    });

    testWidgets('contains zero emoji in all text widgets', (tester) async {
      // Arrange
      const card = ReasoningCard(
        thoughtProcess: sampleThought,
        initiallyExpanded: true,
      );

      // Act
      await tester.pumpWidget(buildTestableWidget(card));
      await tester.pumpAndSettle();

      // Assert
      final textWidgets = tester.widgetList<Text>(find.byType(Text));
      expect(textWidgets, isNotEmpty);
      for (final widget in textWidgets) {
        final data = widget.data ?? widget.textSpan?.toPlainText() ?? '';
        expect(
          containsEmoji(data),
          isFalse,
          reason: 'Text contains emoji: "$data"',
        );
      }
    });

    testWidgets('header touch target height is at least 44px', (tester) async {
      // Arrange
      const card = ReasoningCard(thoughtProcess: sampleThought);

      // Act
      await tester.pumpWidget(buildTestableWidget(card));
      await tester.pumpAndSettle();

      // Assert
      final headerSize = tester.getSize(
        find.byKey(const Key('reasoning_card_header')),
      );
      expect(headerSize.height, greaterThanOrEqualTo(44));
    });

    testWidgets('renders without overflow on 320px narrow screen',
        (tester) async {
      // Arrange: constrain to 320px logical width
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const card = ReasoningCard(
        thoughtProcess: sampleThought,
        initiallyExpanded: true,
      );

      // Act
      await tester.pumpWidget(buildTestableWidget(card));
      await tester.pumpAndSettle();

      // Assert: header + trace visible, no overflow exception
      expect(find.text('Thought Process'), findsOneWidget);
      expect(find.text(sampleThought), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
