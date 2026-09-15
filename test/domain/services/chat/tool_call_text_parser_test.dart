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

  group('ToolCallTextParser hardening', () {
    test('100k unmatched braces do not spin the scanner', () {
      // Arrange
      final raw = '{' * 100000;

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });

    test('100k unmatched brackets do not spin the scanner', () {
      // Arrange
      final raw = '[' * 100000;

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });

    test('a deep balanced payload then a real call still recovers it', () {
      // Arrange
      final open = '{' * 20000;
      final close = '}' * 20000;
      const call = '{"name": "get_battery", "arguments": {}}';
      final raw = '$open$close$call';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('an untagged fence recovers and strips the call', () {
      // Arrange
      const raw = '```\n'
          '{"name": "get_battery", "arguments": {"verbose": true}}\n'
          '```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.cleanedText, isNot(contains('```')));
    });

    test('a dart fence is ignored even with a very long body', () {
      // Arrange
      final raw = '```dart\n'
          '{"name": "delete_all", "arguments": {}}'
          '${'x' * 65505}'
          '```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });

    test('deeply nested arguments cannot escape parse as an Error', () {
      // Arrange
      final open = '[' * 20000;
      final close = ']' * 20000;
      final raw = '{"name": "a", "arguments": $open$close}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });

    test('a call in the middle of a long message is still recovered', () {
      // Arrange
      final head = 'z' * 100000;
      final tail = 'z' * 100000;
      const call = '{"name": "get_battery", "arguments": {}}';
      final raw = '$head$call$tail';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a fenced call wrapped in an object is executed exactly once', () {
      // Arrange
      const raw = '{"a": ```json\n'
          '{"name": "get_battery", "arguments": {}}\n'
          '```}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a call nested in a valid outer object is still recovered', () {
      // Arrange
      const raw = '{"a": 1, "b": {"name": "get_battery", "arguments": {}}}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a mismatched closer before the call does not hide it', () {
      // Arrange
      const raw = '{"a": 1, {"name": "get_battery", "arguments": {}}]';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a json string value is never executed as a call', () {
      // Arrange
      final raw = '{"note": "${'y' * 66000}'
          '{"name": "delete_all", "arguments": {}}" }';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });

    test('a stray quote in a code block does not hide a later call', () {
      // Arrange: the fence body holds an ODD number of double quotes, which
      // used to leave the bracket matcher stuck "inside a string" past the
      // closing fence, so every opener after it lost its end and the real call
      // was dropped.
      const raw = '```dart\n'
          'final s = "unterminated;\n'
          'print(s);\n'
          '```\n'
          '{"name": "get_battery", "arguments": {}}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('an even number of quotes in a code block behaves the same', () {
      // Arrange
      const raw = '```dart\n'
          'print("hi");\n'
          '```\n'
          '{"name": "get_battery", "arguments": {}}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a deep sibling does not hide a shallow call beside it', () {
      // Arrange: the deep run exceeds maxJsonDepth. It must only prune itself,
      // not mark the whole span too deep, or the shallow sibling is skipped.
      final deep = '[' * (ToolCallTextParser.maxJsonDepth + 1) +
          ']' * (ToolCallTextParser.maxJsonDepth + 1);
      final raw = '[$deep, {"name": "get_battery", "arguments": {}}]';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a deep sibling inside a tool_calls envelope keeps the call', () {
      // Arrange
      final deep = '[' * (ToolCallTextParser.maxJsonDepth + 1) +
          ']' * (ToolCallTextParser.maxJsonDepth + 1);
      final raw = '{"tool_calls": [$deep, '
          '{"name": "get_battery", "arguments": {}}]}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a call nested deeper than maxJsonDepth is still recovered', () {
      // Arrange: the CALL ITSELF sits past the documented soft limit. Capping
      // the walk used to prune it while the previously shipped parser found it
      // up to depth ~4000, which made a depth cap a silent coverage regression.
      final n = ToolCallTextParser.maxJsonDepth + 1;
      final raw = '${'[' * n}{"name": "get_battery", "arguments": {}}${']' * n}';

      // Act
      final result = parser.parse(raw, isKnownTool: (n) => n == 'get_battery');

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a call nested thousands of levels deep is recovered without an Error',
        () {
      // Arrange: depth ~4000 was the deepest the shipped parser managed, and
      // ~12000 overflowed its recursive walk. The walk is iterative now, so
      // neither the cap nor the stack is a limit.
      final raw = '${'[' * 6000}{"name": "get_battery", "arguments": {}}'
          '${']' * 6000}';

      // Act
      final result = parser.parse(raw, isKnownTool: (n) => n == 'get_battery');

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a deep-arguments sibling does not discard a shallow call beside it',
        () {
      // jsonEncode is recursive and overflows on a deeply nested arguments
      // map. When that overflow escaped, the caller's catch treated the WHOLE
      // span as unusable and skipped it, silently dropping a legitimate call
      // sitting next to the pathological one. The guard is per-candidate, so
      // only the un-serialisable candidate is skipped.
      final deepArgs = '${'{"k":' * 3400}{} ${'}' * 3400}';
      final raw = '{"tool_calls": [$deepArgs, '
          '{"name": "get_battery", "arguments": {}}]}';

      final result = parser.parse(raw, isKnownTool: (n) => n == 'get_battery');

      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a pathological deep-arguments call never escapes as an Error', () {
      // jsonEncode recurses, and whether a given depth overflows depends on the
      // runtime (JIT and AOT differ), so the recovered-call count here is NOT
      // stable and must not be asserted. What IS invariant: parse() returns
      // normally, and the result is self-consistent -- either the call was
      // recovered and its text stripped, or nothing was accepted and the input
      // is returned untouched.
      final deepArgs = '${'{"k":' * 6000}{} ${'}' * 6000}';
      final raw = '{"name": "get_battery", "arguments": $deepArgs}';

      final result = parser.parse(raw, isKnownTool: (n) => n == 'get_battery');

      if (result.toolCalls.isEmpty) {
        expect(result.cleanedText, equals(raw));
      } else {
        expect(result.toolCalls, hasLength(1));
        expect(result.cleanedText, isNot(contains('get_battery')));
      }
    });

    test('a deep nest with no call stays bounded and byte-identical', () {
      // The walk must not throw and must leave the text alone when there is
      // nothing to recover, however deep the payload is.
      final raw = '[' * 2000 + ']' * 2000;

      final result = parser.parse(raw);

      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });

    test('a call whose arguments contain a fence opener is still recovered', () {
      // Arrange
      const raw = '{"name":"get_battery","arguments":{"m":"```"}} ```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
      expect(result.toolCalls.single.argumentsFragment, '{"m":"```"}');
    });

    test('a fence opener inside arguments does not hide a following call', () {
      // Arrange
      const raw = '{"name":"write_file","arguments":{"content":"```dart"}} ```\n'
          '{"name":"list_dir","arguments":{"p":"/"}}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(2));
      expect(result.toolCalls[0].name, 'write_file');
      expect(result.toolCalls[1].name, 'list_dir');
    });

    test('a realistic file-writing message with an embedded code fence is recovered',
        () {
      // Arrange
      const raw = 'Here you go:\n'
          '{"name":"write_file","arguments":{"path":"x.md","content":"```python"}}'
          ' done\n```\n';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'write_file');
    });

    test('a call nested under a plain key beside a fence opener is still recovered',
        () {
      // Arrange
      const raw = '{"note":{"name":"get_battery","arguments":{"m":"```"}}} ```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a fence opener in arguments after many unmatched openers is still recovered',
        () {
      // Arrange
      final raw = '{"' * 100 +
          '{"name":"get_battery","arguments":{"m":"```"}} ```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'get_battery');
    });

    test('a fenced payload does not make the scan quadratic', () {
      // Arrange
      final raw = '${'{"a":' * 8000}```dart\n${'}' * 8000}\n```';

      // Act
      final sw = Stopwatch()..start();
      final result = parser.parse(raw);
      sw.stop();

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: 'fenced payload must not be quadratic (was ~2400ms when the '
              'fence-blind fallback ran unconditionally)');
    });

    test('a fence opener in prose does not change which call is recovered', () {
      // Arrange
      const raw = '{"name":"write_file","arguments":{"content":"```dart"}} '
          'Use "```" to start a block. '
          '{"name":"list_dir","arguments":{"p":"/"}}';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, hasLength(1));
      expect(result.toolCalls.single.name, 'write_file');
    });

    test('a tagged fence is still never executed', () {
      // Arrange
      const tags = ['dart', 'text', 'jsonc', 'JSON5', 'python', 'bash'];

      // Act & Assert
      for (final tag in tags) {
        final raw = '```$tag\n{"name":"factory_reset","arguments":{}}\n```';
        final result = parser.parse(raw);
        expect(result.toolCalls, isEmpty, reason: 'tag: $tag');
      }
    });

    test('a zero-call result still returns the input byte-identically', () {
      // Arrange
      const raw = '```dart\n{"name":"factory_reset","arguments":{}}\n```';

      // Act
      final result = parser.parse(raw);

      // Assert
      expect(result.toolCalls, isEmpty);
      expect(result.cleanedText, equals(raw));
    });
  });
}
