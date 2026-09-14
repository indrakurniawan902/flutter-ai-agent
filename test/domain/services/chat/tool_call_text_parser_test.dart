import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ai_agent/domain/services/chat/tool_call_text_parser.dart';

void main() {
  const parser = ToolCallTextParser();

  group('ToolCallTextParser fenced blocks', () {
    test('fenced json with a single call extracts and removes the block', () {
      // Arrange
      const raw =
          'Here you go:\n```json\n{"name": "get_battery", "arguments": {"verbose": true}}\n```\nDone.';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.toolCalls.single.index, 0);
      expect(result.toolCalls.single.id, isNull);
      expect(
        result.toolCalls.single.argumentsFragment,
        jsonEncode({'verbose': true}),
      );
      expect(result.cleanedText, 'Here you go:\n\nDone.');
      expect(result.cleanedText, isNot(contains('```')));
    });

    test('fenced tool_call info string extracts the call', () {
      // Arrange
      const raw =
          '```tool_call\n{"name": "get_battery", "arguments": {"verbose": true}}\n```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(
        result.toolCalls.single.argumentsFragment,
        jsonEncode({'verbose': true}),
      );
      expect(result.cleanedText, '');
    });

    test('uppercase JSON info string is accepted', () {
      // Arrange
      const raw =
          '```JSON\n{"name": "get_battery", "arguments": {"verbose": true}}\n```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.cleanedText, '');
    });

    test('body on the same line as the info string is accepted', () {
      // Arrange
      const raw =
          'Before ```json {"name": "get_battery", "arguments": {}}``` After';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.toolCalls.single.argumentsFragment, jsonEncode(<String, dynamic>{}));
      expect(result.cleanedText, 'Before  After');
    });

    test('prose before and after the fenced block is preserved verbatim', () {
      // Arrange
      const raw =
          'I will check the battery.\n\n```json\n{"name": "get_battery", "arguments": {}}\n```\n\nStand by.';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.cleanedText, 'I will check the battery.\n\nStand by.');
      expect(result.cleanedText, contains('I will check the battery.'));
      expect(result.cleanedText, contains('Stand by.'));
      expect(result.cleanedText, isNot(contains('get_battery')));
    });

    test('fenced json array of two calls yields indices 0 and 1', () {
      // Arrange
      const raw =
          '```json\n[{"name": "a", "arguments": {"x": 1}}, {"name": "b", "arguments": {"y": 2}}]\n```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(2));
      expect(result.toolCalls[0].index, 0);
      expect(result.toolCalls[0].name, 'a');
      expect(result.toolCalls[0].argumentsFragment, jsonEncode({'x': 1}));
      expect(result.toolCalls[1].index, 1);
      expect(result.toolCalls[1].name, 'b');
      expect(result.toolCalls[1].argumentsFragment, jsonEncode({'y': 2}));
      expect(result.cleanedText, '');
    });

    test('message consisting only of the fenced block cleans to empty', () {
      // Arrange
      const raw = '```json\n{"name": "a", "arguments": {}}\n```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.cleanedText, '');
    });

    test('truncated JSON inside a fence leaves the text untouched', () {
      // Arrange
      const raw = '```json\n{"name": "a", "arguments":\n```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });
  });

  group('ToolCallTextParser bare JSON', () {
    test('bare JSON object embedded in prose is extracted and removed', () {
      // Arrange
      const raw =
          'The call is {"name": "get_battery", "arguments": {"a": 1}} now.';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.toolCalls.single.argumentsFragment, jsonEncode({'a': 1}));
      expect(result.cleanedText, 'The call is  now.');
    });

    test('bare function envelope is extracted', () {
      // Arrange
      const raw =
          'x {"function": {"name": "get_battery", "arguments": {"a": 1}}} y';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.toolCalls.single.argumentsFragment, jsonEncode({'a': 1}));
    });

    test('tool_calls envelope extracts every call', () {
      // Arrange
      const raw =
          '{"tool_calls": [{"function": {"name": "a", "arguments": {}}}, {"name": "b", "arguments": {"k": 1}}]}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(2));
      expect(result.toolCalls[0].name, 'a');
      expect(result.toolCalls[0].index, 0);
      expect(result.toolCalls[1].name, 'b');
      expect(result.toolCalls[1].index, 1);
      expect(result.toolCalls[1].argumentsFragment, jsonEncode({'k': 1}));
    });

    test('arguments given as a JSON string is used verbatim', () {
      // Arrange
      const raw = r'{"name": "search", "arguments": "{\"query\":\"x\"}"}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'search');
      expect(result.toolCalls.single.argumentsFragment, '{"query":"x"}');
    });

    test('a JSON blob that is not a tool call leaves the text unchanged', () {
      // Arrange
      const raw = 'Battery level is {"battery": 85} percent.';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });

    test('a name without an arguments key is rejected', () {
      // Arrange
      const raw = 'Calling {"name": "get_battery"} now.';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });
  });

  group('ToolCallTextParser mixed and malformed input', () {
    test('a fenced block plus a bare object yields two calls', () {
      // Arrange
      const raw =
          '```json\n{"name": "a", "arguments": {}}\n```\nand {"name": "b", "arguments": {}}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(2));
      expect(result.toolCalls[0].name, 'a');
      expect(result.toolCalls[0].index, 0);
      expect(result.toolCalls[1].name, 'b');
      expect(result.toolCalls[1].index, 1);
      expect(result.cleanedText, 'and');
    });

    test('nested JSON inside a fenced body is not counted twice', () {
      // Arrange
      const raw =
          '```json\n{"name": "a", "arguments": {"nested": {"x": 1}}}\n```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.cleanedText, '');
    });

    test('unknown tool name is rejected and the text is untouched', () {
      // Arrange
      const raw = '```json\n{"name": "mystery_tool", "arguments": {}}\n```';

      // Act
      final result = parser.parse(raw, isKnownTool: (_) => false);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });

    test('known tool name is accepted and the block is removed', () {
      // Arrange
      const raw = '```json\n{"name": "get_battery", "arguments": {}}\n```';

      // Act
      final result = parser.parse(raw, isKnownTool: (name) => name == 'get_battery');

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.cleanedText, '');
    });

    test('a fence with an unrelated info string is ignored', () {
      // Arrange
      const raw = '```dart\n{"name": "a", "arguments": {}}\n```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });

    test('plain prose without JSON leaves the text unchanged', () {
      // Arrange
      const raw = 'Just a normal answer with no tool calls at all.';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });

    test('malformed input never spins the scanner and stays unchanged', () {
      // Arrange
      const inputs = <String>[
        '{"name": "a", "arguments": {"x": ',
        '[{{{',
        '"unterminated',
      ];

      // Act & Assert
      for (final raw in inputs) {
        final result = parser.parse(raw);
        expect(result.toolCalls, isEmpty, reason: 'input: $raw');
        expect(result.cleanedText, equals(raw), reason: 'input: $raw');
      }
    });
  });

  group('ToolCallTextParser bounded scan runtime', () {
    test('oversized adversarial input stays linear and byte-identical', () {
      // Arrange
      final unterminated = '"unterminated' * 5000;
      final inputs = <String>[
        '{' * 100000,
        '[' * 100000,
        '{{' * 50000,
        '{"name": "a", "arguments": {"x": $unterminated',
      ];
      final stopwatch = Stopwatch()..start();

      // Act & Assert
      for (final raw in inputs) {
        final result = parser.parse(raw);
        expect(result.toolCalls, isEmpty, reason: 'len=${raw.length}');
        expect(
          identical(result.cleanedText, raw),
          isTrue,
          reason: 'len=${raw.length}',
        );
      }
      stopwatch.stop();
      expect(stopwatch.elapsedMilliseconds, lessThan(5000));
    });
  });

  group('ToolCallTextParser untagged fences', () {
    test('untagged fence containing a call is recovered and stripped', () {
      // Arrange
      const raw =
          'Here:\n```\n{"name": "get_battery", "arguments": {"verbose": true}}\n```\nDone.';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(
        result.toolCalls.single.argumentsFragment,
        jsonEncode({'verbose': true}),
      );
      expect(result.cleanedText, isNot(contains('```')));
      expect(result.cleanedText, isNot(contains('get_battery')));
    });

    test('untagged fence with prose body leaves the text byte-identical', () {
      // Arrange
      const raw = 'Before\n```\njust a plain code snippet\n```\nAfter';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(identical(result.cleanedText, raw), isTrue);
    });

    test('jsonc info string is treated like json', () {
      // Arrange
      const raw =
          '```jsonc\n{"name": "get_battery", "arguments": {"verbose": true}}\n```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.cleanedText, '');
    });

    test('text info string is treated like json', () {
      // Arrange
      const raw =
          '```text\n{"name": "get_battery", "arguments": {"verbose": true}}\n```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.cleanedText, '');
    });

    test('a non-empty unrecognised info string is still ignored', () {
      // Arrange
      const raw = '```dart\n{"name": "a", "arguments": {}}\n```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(identical(result.cleanedText, raw), isTrue);
    });
  });

  group('ToolCallTextParser maxScanLength cap', () {
    test('a call beyond the cap is not recovered and the text is unchanged', () {
      // Arrange
      final raw = 'x' * 300 + '{"name": "get_battery", "arguments": {}}';

      // Act
      final result = parser.parse(raw, maxScanLength: 256);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(identical(result.cleanedText, raw), isTrue);
    });

    test('a call inside the cap is recovered', () {
      // Arrange
      final raw = '{"name": "get_battery", "arguments": {}}${'x' * 300}';

      // Act
      final result = parser.parse(raw, maxScanLength: 256);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a call inside the cap is stripped while the tail is preserved', () {
      // Arrange
      final raw =
          '{"name": "get_battery", "arguments": {}}${'y' * 300}${'TAIL' * 100}';

      // Act
      final result = parser.parse(raw, maxScanLength: 256);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.cleanedText, isNot(contains('get_battery')));
      expect(result.cleanedText, contains('TAIL'));
    });
  });

  group('ToolCallTextParser nested bare spans', () {
    test('a nested tool-call-shaped argument is not accepted a second time', () {
      // Arrange
      const raw =
          '{"name": "execute_tool", "arguments": {"name": "get_battery", "arguments": {}}}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'execute_tool');
      expect(
        result.toolCalls.single.argumentsFragment,
        jsonEncode({
          'name': 'get_battery',
          'arguments': <String, dynamic>{},
        }),
      );
      expect(result.cleanedText, isNot(contains('get_battery')));
    });

    test('a nested tool-call shape outside an accepted span is still recovered',
        () {
      // Arrange
      const raw = 'x {"battery": 85} {"name": "get_battery", "arguments": {}} y';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a fenced block plus a bare object still yields two calls in order',
        () {
      // Arrange
      const raw =
          '```json\n{"name": "a", "arguments": {}}\n```\nand {"name": "b", "arguments": {}}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(2));
      expect(result.toolCalls[0].name, 'a');
      expect(result.toolCalls[1].name, 'b');
    });
  });

  group('ToolCallTextParser nested recovery', () {
    test('a call nested in a rejected action/payload wrapper is recovered', () {
      // Arrange
      const raw =
          '{"action": "call_tool", "payload": {"name": "get_battery", "arguments": {"verbose": true}}}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.cleanedText, isNot(contains('get_battery')));
    });

    test('a call nested in a rejected array wrapper is recovered', () {
      // Arrange
      const raw = '[Tool call: {"name": "get_battery", "arguments": {}}]';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.cleanedText, isNot(contains('get_battery')));
    });

    test('a call nested beside malformed siblings is recovered', () {
      // Arrange
      const raw = 'x [{"name": "a", "arguments": {}}, broken] y';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'a');
      expect(result.cleanedText, isNot(contains('a')));
    });

    test('a call nested two rejected wrappers deep is recovered', () {
      // Arrange
      const raw =
          '{"wrapper": {"call": {"name": "get_battery", "arguments": {}}}}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.cleanedText, isNot(contains('get_battery')));
    });

    test('an accepted span is never scanned again for nested calls', () {
      // Arrange
      const raw =
          '{"name": "execute_tool", "arguments": {"name": "get_battery", "arguments": {}}}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'execute_tool');
    });

    test('a rejected wrapper keeps its prose while the inner span is stripped',
        () {
      // Arrange
      const raw =
          '{"action": "call_tool", "payload": {"name": "get_battery", "arguments": {"verbose": true}}}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.cleanedText, contains('"action"'));
      expect(result.cleanedText, contains('"payload"'));
      expect(result.cleanedText, isNot(contains('get_battery')));
    });
  });

  group('ToolCallTextParser nesting budget', () {
    test('deeply nested unmatched brackets terminate within budget', () {
      // Arrange
      final raw = '${'[' * 40000}${']' * 40000}';
      final stopwatch = Stopwatch()..start();

      // Act
      final result = parser.parse(raw);

      // Assert
      stopwatch.stop();
      expect(result.toolCalls, isEmpty);
      expect(identical(result.cleanedText, raw), isTrue);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('deeply nested rejected objects terminate within budget', () {
      // Arrange
      final raw = '${'{"a": ' * 20000}1${'}' * 20000}';
      final stopwatch = Stopwatch()..start();

      // Act
      final result = parser.parse(raw);

      // Assert
      stopwatch.stop();
      expect(result.toolCalls, isEmpty);
      expect(identical(result.cleanedText, raw), isTrue);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });
  });

  group('ToolCallTextParser span attempt budget', () {
    test('a call after many non-envelope objects is still recovered', () {
      // Arrange
      final raw = '{"a": 1} ' * 300 +
          '{"name": "get_battery", "arguments": {"verbose": true}}';
      final stopwatch = Stopwatch()..start();

      // Act
      final result = parser.parse(raw);

      // Assert
      stopwatch.stop();
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.cleanedText, isNot(contains('get_battery')));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 2)));
    });

    test('a fenced call after many non-envelope objects is still recovered',
        () {
      // Arrange
      final raw = '{"a": 1} ' * 300 +
          '```json\n{"name": "get_battery", "arguments": {}}\n```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('many non-envelope objects alone stay byte-identical', () {
      // Arrange
      final raw = '{"a": 1} ' * 300;

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(identical(result.cleanedText, raw), isTrue);
    });

    test('the budget does not starve the registry check', () {
      // Arrange
      final raw =
          '{"a": 1} ' * 300 + '{"name": "get_battery", "arguments": {}}';

      // Act
      final result = parser.parse(
        raw,
        isKnownTool: (name) => name == 'get_battery',
      );

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });
  });
}
