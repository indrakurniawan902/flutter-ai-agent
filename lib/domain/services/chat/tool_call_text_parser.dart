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

  /// Upper bound on how much of the message is scanned for tool calls.
  ///
  /// `parse` runs synchronously on the UI isolate, so a compromised or
  /// adversarial model can stall the whole app by streaming a huge payload
  /// (e.g. 100k unmatched `{`). Capping the scanned window keeps the
  /// worst-case work bounded while still covering any realistic payload.
  static const int maxScanLength = 64 * 1024;

  /// Safety-valve cap on candidate-span decode attempts per parse.
  ///
  /// Attempts at one nesting level cover disjoint spans, so their decode work
  /// is bounded by the region length, and across at most [maxNestingDepth]
  /// levels by `maxNestingDepth * maxScanLength`. The counter is therefore only
  /// a backstop against pathological input, not the primary bound; a tight cap
  /// silently starves a real call that follows a few hundred echoed JSON
  /// objects, which is exactly the weak-model behaviour this parser targets.
  static const int maxSpanAttempts = 8192;

  /// How deep the "rejected wrapper -> retry its interior" recursion may go.
  ///
  /// A legit message never nests tool-call wrappers deeper than this; the bound
  /// keeps pathological nesting cheap even when every level must be retried.
  static const int maxNestingDepth = 16;

  /// [isKnownTool] lets the caller reject names the registry does not know.
  /// [maxScanLength] bounds the scanned window; text past it is untouched.
  ToolCallTextParseResult parse(
    String rawText, {
    bool Function(String name)? isKnownTool,
    int maxScanLength = maxScanLength,
  }) {
    final scanText = rawText.length > maxScanLength
        ? rawText.substring(0, maxScanLength)
        : rawText;

    final accepted = <_AcceptedSpan>[];
    _scan(scanText, isKnownTool, accepted);

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

  /// Single left-to-right pass over the scanned window. Tracking string state,
  /// bracket nesting and fence spans lets every character be visited once: the
  /// previous per-opener rescan was quadratic and could freeze the isolate.
  ///
  /// A rejected outermost span is not swallowed: its interior is rescanned
  /// recursively so a valid tool-call object wrapped in a non-envelope object
  /// (e.g. `{"action": ..., "payload": {...}}`) is still recovered, matching
  /// the historical per-opener behaviour. The [maxSpanAttempts] and
  /// [maxNestingDepth] budgets keep that retry bounded.
  void _scan(
    String text,
    bool Function(String name)? isKnownTool,
    List<_AcceptedSpan> accepted,
  ) {
    _scanRegion(text, 0, text.length, isKnownTool, accepted, _ScanBudget(), 0);
  }

  /// Scans `[regionStart, regionEnd)` of [text]. A closed bracket pair that
  /// empties the stack is an outermost span of this region: if it is not a tool
  /// call, its interior is scanned recursively so nested openers get their own
  /// attempt in increasing index order.
  void _scanRegion(
    String text,
    int regionStart,
    int regionEnd,
    bool Function(String name)? isKnownTool,
    List<_AcceptedSpan> accepted,
    _ScanBudget budget,
    int depth,
  ) {
    final closers = <int>[];
    final openers = <int>[];
    var inString = false;
    var i = regionStart;
    while (i < regionEnd) {
      if (!inString && i + 3 <= regionEnd && text.startsWith('```', i)) {
        final fence = _readFence(text, i, regionEnd);
        if (fence == null) {
          // Unclosed fence: skip the marker and keep scanning, matching the
          // historical "not a fence" treatment.
          i += 3;
          continue;
        }
        if (_isToolCallInfo(fence.info)) {
          final calls = _attemptSpan(
            text,
            fence.bodyStart,
            fence.bodyEnd,
            isKnownTool,
            budget,
          );
          if (calls != null) {
            accepted.add(_AcceptedSpan(fence.start, fence.end, calls));
          }
        }
        // Every closed fence is consumed as a span, recognised or not, so the
        // bare scanner never double-reads its body.
        i = fence.end;
        continue;
      }

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
        i++;
        continue;
      }
      if (c == 0x7B || c == 0x5B) {
        closers.add(c == 0x7B ? 0x7D : 0x5D);
        openers.add(i);
        i++;
        continue;
      }
      if (c == 0x7D || c == 0x5D) {
        if (closers.isNotEmpty && closers.last == c) {
          closers.removeLast();
          final start = openers.removeLast();
          if (closers.isEmpty) {
            final end = i + 1;
            final calls = _attemptSpan(text, start, end, isKnownTool, budget);
            if (calls != null) {
              accepted.add(_AcceptedSpan(start, end, calls));
            } else if (depth < maxNestingDepth) {
              // Rejected wrapper: retry its interior so nested tool-call
              // objects are recovered instead of being lost forever.
              _scanRegion(
                text,
                start + 1,
                end - 1,
                isKnownTool,
                accepted,
                budget,
                depth + 1,
              );
            }
            // Resume past the span. An accepted span must never be rescanned
            // (no double execution); a rejected one was already rescanned
            // above, so its interior is not re-read here either.
            i = end;
            continue;
          }
        }
        i++;
        continue;
      }
      i++;
    }
  }

  /// Decodes one candidate span and returns its validated calls, or null when
  /// the span is malformed or carries no tool-call envelope. Every attempt
  /// spends one unit of [budget] so adversarial nesting stays bounded.
  List<_ValidatedCall>? _attemptSpan(
    String text,
    int start,
    int end,
    bool Function(String name)? isKnownTool,
    _ScanBudget budget,
  ) {
    if (!budget.claim()) return null;
    final decoded = _tryDecode(text.substring(start, end));
    if (decoded == null) return null;
    final calls = _validate(_extract(decoded), isKnownTool);
    return calls.isEmpty ? null : calls;
  }

  /// Info strings we attempt to decode as a tool call. The empty string is
  /// included because weak models routinely omit the language tag.
  bool _isToolCallInfo(String info) =>
      info.isEmpty ||
      info == 'json' ||
      info == 'tool_call' ||
      info == 'text' ||
      info == 'jsonc' ||
      info == 'json5';

  _Fence? _readFence(String text, int start, int limit) {
    var k = start + 3;
    while (k < limit && !_isInfoTerminator(text.codeUnitAt(k))) {
      k++;
    }
    final info = text.substring(start + 3, k).trim().toLowerCase();
    final close = text.indexOf('```', k);
    // A closer outside the current region means the fence is unclosed here;
    // treating it as such keeps nested regions from swallowing outer content.
    if (close == -1 || close + 3 > limit) return null;
    return _Fence(start, close + 3, info, k, close);
  }

  bool _isInfoTerminator(int c) =>
      c == 0x20 ||
      c == 0x09 ||
      c == 0x0A ||
      c == 0x0D ||
      c == 0x7B ||
      c == 0x5B;

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

/// Mutable per-parse counter for [ToolCallTextParser.maxSpanAttempts]. Lives
/// outside the parser so the parser itself stays const-constructible and
/// stateless.
class _ScanBudget {
  int remaining = ToolCallTextParser.maxSpanAttempts;

  bool claim() {
    if (remaining <= 0) return false;
    remaining--;
    return true;
  }
}
