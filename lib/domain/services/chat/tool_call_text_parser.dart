import 'dart:convert';

import 'package:flutter_ai_agent/domain/entities/chat/tool_call_delta.dart';

/// Outcome of scanning assistant text for tool calls emitted as markdown/JSON.
class ToolCallTextParseResult {
  final List<ToolCallDelta> toolCalls;
  final String cleanedText;
  const ToolCallTextParseResult({
    required this.toolCalls,
    required this.cleanedText,
  });
  bool get hasToolCalls => toolCalls.isNotEmpty;
}

/// Recovers tool calls that weak models emit as assistant text (a fenced
/// `json`/`tool_call` block or a bare JSON object) and strips the consumed
/// spans out of the user-visible text.
class ToolCallTextParser {
  const ToolCallTextParser();

  /// [isKnownTool] lets the caller reject names the registry does not know.
  ToolCallTextParseResult parse(
    String rawText, {
    bool Function(String name)? isKnownTool,
  }) {
    final fences = _findFences(rawText);
    final accepted = <_AcceptedSpan>[];

    for (final fence in fences) {
      if (fence.info != 'json' && fence.info != 'tool_call') continue;
      final decoded = _tryDecode(rawText.substring(fence.bodyStart, fence.bodyEnd));
      if (decoded == null) continue;
      final calls = _validate(_extract(decoded), isKnownTool);
      if (calls.isEmpty) continue;
      accepted.add(_AcceptedSpan(fence.start, fence.end, calls));
    }

    _scanBare(rawText, fences, isKnownTool, accepted);

    if (accepted.isEmpty) {
      return ToolCallTextParseResult(toolCalls: const [], cleanedText: rawText);
    }

    accepted.sort((a, b) => a.start.compareTo(b.start));
    final toolCalls = <ToolCallDelta>[];
    for (final span in accepted) {
      for (final call in span.calls) {
        toolCalls.add(ToolCallDelta(
          index: toolCalls.length,
          name: call.name,
          argumentsFragment: call.argumentsFragment,
        ));
      }
    }

    return ToolCallTextParseResult(
      toolCalls: toolCalls,
      cleanedText: _clean(rawText, accepted),
    );
  }

  List<_Fence> _findFences(String text) {
    final fences = <_Fence>[];
    var i = 0;
    while (i + 3 <= text.length) {
      if (text.startsWith('```', i)) {
        var k = i + 3;
        while (k < text.length && !_isInfoTerminator(text.codeUnitAt(k))) {
          k++;
        }
        final info = text.substring(i + 3, k).trim().toLowerCase();
        final close = text.indexOf('```', k);
        if (close == -1) {
          i += 3;
          continue;
        }
        fences.add(_Fence(i, close + 3, info, k, close));
        i = close + 3;
      } else {
        i++;
      }
    }
    return fences;
  }

  bool _isInfoTerminator(int c) =>
      c == 0x20 ||
      c == 0x09 ||
      c == 0x0A ||
      c == 0x0D ||
      c == 0x7B ||
      c == 0x5B;

  void _scanBare(
    String text,
    List<_Fence> fences,
    bool Function(String name)? isKnownTool,
    List<_AcceptedSpan> accepted,
  ) {
    var i = 0;
    var inString = false;
    while (i < text.length) {
      if (_insideFence(fences, i)) {
        i++;
        continue;
      }
      final c = text[i];
      if (inString) {
        if (c == '\\') {
          i += 2;
          continue;
        }
        if (c == '"') inString = false;
        i++;
        continue;
      }
      if (c == '"') {
        inString = true;
        i++;
        continue;
      }
      if (c == '{' || c == '[') {
        final end = _balancedEnd(text, i);
        if (end != null) {
          final decoded = _tryDecode(text.substring(i, end));
          if (decoded != null) {
            final calls = _validate(_extract(decoded), isKnownTool);
            if (calls.isNotEmpty) {
              accepted.add(_AcceptedSpan(i, end, calls));
              i = end;
              continue;
            }
          }
        }
      }
      i++;
    }
  }

  int? _balancedEnd(String text, int start) {
    final closers = <int>[];
    var i = start;
    var inString = false;
    while (i < text.length) {
      final c = text.codeUnitAt(i);
      if (inString) {
        if (c == 0x5C) {
          i += 2;
          continue;
        }
        if (c == 0x22) inString = false;
        i++;
        continue;
      }
      if (c == 0x22) {
        inString = true;
      } else if (c == 0x7B) {
        closers.add(0x7D);
      } else if (c == 0x5B) {
        closers.add(0x5D);
      } else if (c == 0x7D || c == 0x5D) {
        if (closers.isEmpty || closers.last != c) return null;
        closers.removeLast();
        if (closers.isEmpty) return i + 1;
      }
      i++;
    }
    return null;
  }

  bool _insideFence(List<_Fence> fences, int index) {
    for (final fence in fences) {
      if (index >= fence.start && index < fence.end) return true;
    }
    return false;
  }

  List<_RawCandidate> _extract(dynamic value) {
    if (value is Map) {
      final name = value['name'];
      if (name is String && name.isNotEmpty && value.containsKey('arguments')) {
        return [_RawCandidate(name, value['arguments'])];
      }
      final function = value['function'];
      if (function is Map) {
        final fnName = function['name'];
        if (fnName is String &&
            fnName.isNotEmpty &&
            function.containsKey('arguments')) {
          return [_RawCandidate(fnName, function['arguments'])];
        }
      }
      final toolCalls = value['tool_calls'];
      if (toolCalls is List) {
        final out = <_RawCandidate>[];
        for (final element in toolCalls) {
          out.addAll(_extract(element));
        }
        return out;
      }
      return const [];
    }
    if (value is List) {
      final out = <_RawCandidate>[];
      for (final element in value) {
        out.addAll(_extract(element));
      }
      return out;
    }
    return const [];
  }

  List<_ValidatedCall> _validate(
    List<_RawCandidate> candidates,
    bool Function(String name)? isKnownTool,
  ) {
    final out = <_ValidatedCall>[];
    for (final candidate in candidates) {
      final arguments = candidate.arguments;
      String fragment;
      if (arguments is Map) {
        fragment = jsonEncode(arguments);
      } else if (arguments is String) {
        final trimmed = arguments.trim();
        if (_tryDecode(trimmed) is! Map) continue;
        fragment = trimmed;
      } else {
        continue;
      }
      if (isKnownTool != null && !isKnownTool(candidate.name)) continue;
      out.add(_ValidatedCall(candidate.name, fragment));
    }
    return out;
  }

  String _clean(String rawText, List<_AcceptedSpan> spans) {
    final buffer = StringBuffer();
    var cursor = 0;
    for (final span in spans) {
      if (span.start < cursor) continue;
      buffer.write(rawText.substring(cursor, span.start));
      cursor = span.end;
    }
    buffer.write(rawText.substring(cursor));
    return buffer.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }

  dynamic _tryDecode(String source) {
    try {
      return jsonDecode(source);
    } catch (_) {
      return null;
    }
  }
}

class _Fence {
  final int start;
  final int end;
  final String info;
  final int bodyStart;
  final int bodyEnd;
  const _Fence(this.start, this.end, this.info, this.bodyStart, this.bodyEnd);
}

class _RawCandidate {
  final String name;
  final dynamic arguments;
  const _RawCandidate(this.name, this.arguments);
}

class _ValidatedCall {
  final String name;
  final String argumentsFragment;
  const _ValidatedCall(this.name, this.argumentsFragment);
}

class _AcceptedSpan {
  final int start;
  final int end;
  final List<_ValidatedCall> calls;
  const _AcceptedSpan(this.start, this.end, this.calls);
}
