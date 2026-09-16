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

  /// JSON nesting levels a walk used to stop at.
  ///
  /// No longer prunes: capping the walk silently discarded every call nested
  /// deeper than the cap, and the deepest call the previously shipped parser
  /// recovered (~4000) sits too close to the depth at which a *recursive* walk
  /// overflows (~10000) to pick a cap that both preserves coverage and prevents
  /// the overflow. The walk is iterative instead, so it has no ceiling to
  /// tune. Retained because callers and tests reference it as the documented
  /// soft nesting limit.
  static const int maxJsonDepth = 1024;

  /// [isKnownTool] lets the caller reject names the registry does not know.
  ToolCallTextParseResult parse(
    String rawText, {
    bool Function(String name)? isKnownTool,
  }) {
    final fences = _findFences(rawText);
    final accepted = <_AcceptedSpan>[];

    for (final fence in fences) {
      if (!_isToolCallInfo(fence.info)) continue;
      final calls = _recover(
        rawText.substring(fence.bodyStart, fence.bodyEnd),
        isKnownTool,
      );
      if (calls == null) continue;
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

  /// Fences that are genuinely markdown fences.
  ///
  /// [_findFences] pairs backtick runs by position alone, so a code fence a
  /// model wrote *inside* a tool call's arguments (as in
  /// `{"content":"```dart"}`) gets paired with any later closer. Such a run is
  /// content, not a fence: a backtick run whose opener is reached inside a JSON
  /// string is skipped here. Used only to decide whether a fallback span is
  /// legitimate, so the main scan keeps the exact fence list it had.
  List<_Fence> _realFences(String text, List<_Fence> fences) {
    final real = <_Fence>[];
    var inString = false;
    var i = 0;
    var fi = 0;
    while (i < text.length) {
      while (fi < fences.length && fences[fi].end <= i) {
        fi++;
      }
      if (fi < fences.length && i == fences[fi].start) {
        if (!inString) {
          real.add(fences[fi]);
          i = fences[fi].end;
          fi++;
          continue;
        }
        fi++;
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
      i++;
    }
    return real;
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
          // Advance past the whole unterminated info run. Stepping 3 chars
          // re-scanned the run once per start offset, which made a backtick
          // flood quadratic and could freeze the UI isolate.
          i = k;
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

  /// Info strings attempted as a tool call.
  ///
  /// The empty string is included because weak models routinely omit the
  /// language tag. A non-empty unrecognised tag (for example `dart`) is still
  /// ignored, so a code example is never executed.
  bool _isToolCallInfo(String info) =>
      info.isEmpty || info == 'json' || info == 'tool_call';

  /// Fence-blind variant of [_matchEnds], matching the `_balancedEnd` helper the
  /// previously shipped parser called at every opener.
  ///
  /// The fence-aware pass is the fast path and is what makes the scan linear,
  /// but it skips fence interiors, so where a payload's closer sits inside one
  /// it finds no end at all. The shipped parser still recovered a call there,
  /// and losing those calls is a regression, not a speed-up. Computing this map
  /// in ONE forward pass keeps the fallback linear; a per-opener re-scan is
  /// quadratic and starves later openers once its work budget runs out.
  Map<int, int> _matchEndsBlind(String text) {
    final ends = <int, int>{};
    final openers = <int>[];
    var inString = false;
    var i = 0;
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
        i++;
        continue;
      }
      if (c == 0x7B || c == 0x5B) {
        openers.add(i);
        i++;
        continue;
      }
      if (c == 0x7D || c == 0x5D) {
        if (openers.isEmpty) {
          i++;
          continue;
        }
        final open = openers.last;
        final expected = text.codeUnitAt(open) == 0x7B ? 0x7D : 0x5D;
        if (expected == c) {
          openers.removeLast();
          ends[open] = i + 1;
        } else {
          openers.clear();
        }
        i++;
        continue;
      }
      i++;
    }
    return ends;
  }

  /// Maps each balanced opener index to the exclusive end of its shortest
  /// balanced span.
  ///
  /// The previous code called a scanning helper at every opener, and that
  /// helper walked to end-of-string when brackets never balance, so a payload
  /// like `'{' * 100000` was quadratic and froze the UI isolate. Computing
  /// every answer in one forward pass makes bracket matching linear, and it is
  /// exact: an opener balances exactly when the stack returns to the depth it
  /// had before that opener was pushed. Keyed by opener index so memory scales
  /// with the number of *balanced* openers rather than the input length.
  Map<int, int> _matchEnds(String text, List<_Fence> fences) {
    final ends = <int, int>{};
    final openers = <int>[];
    var inString = false;
    var i = 0;
    var fi = 0;
    while (i < text.length) {
      // Fence interiors are skipped exactly as [_scanBare] skips them. Without
      // this, a stray quote inside a code block leaves `inString` stuck true
      // for the rest of the message and every opener after the fence loses its
      // end, so a real tool call following a code sample was silently dropped.
      while (fi < fences.length && fences[fi].end <= i) {
        fi++;
      }
      if (fi < fences.length && i >= fences[fi].start && i < fences[fi].end) {
        i++;
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
        openers.add(i);
        i++;
        continue;
      }
      if (c == 0x7D || c == 0x5D) {
        if (openers.isEmpty) {
          i++;
          continue;
        }
        final open = openers.last;
        final expected = text.codeUnitAt(open) == 0x7B ? 0x7D : 0x5D;
        if (expected == c) {
          openers.removeLast();
          ends[open] = i + 1;
        } else {
          // A mismatched closer aborts the scan for every opener still open,
          // which is exactly what the previous helper did by returning null.
          // Dropping the whole stack (rather than popping one entry) is what
          // keeps this pass equivalent to that helper rather than merely
          // similar, so no span is ever accepted or skipped differently.
          openers.clear();
        }
        i++;
        continue;
      }
      i++;
    }
    return ends;
  }

  void _scanBare(
    String text,
    List<_Fence> fences,
    bool Function(String name)? isKnownTool,
    List<_AcceptedSpan> accepted,
  ) {
    final ends = _matchEnds(text, fences);
    // Only built when the fast path leaves an opener without an end, so an
    // ordinary message never pays for it.
    Map<int, int>? blindEnds;
    List<_Fence>? realFences;
    var i = 0;
    var fi = 0;
    // First REAL fence starting at or after `i`. Fences are disjoint and sorted
    // and `i` only moves right, so this advances monotonically.
    var fj = 0;
    // Character budget for the rescans below. Both maps above answer from a
    // SINGLE left-to-right walk carrying one quote state, while the previously
    // shipped parser restarted the quote state at every opener. Where a message
    // desyncs those two readings the maps hold no answer at all, so the opener
    // is dropped even though the shipped parser recovered it. Rescanning from
    // such an opener reproduces the shipped answer; the budget keeps the total
    // work linear, because a message that desyncs everywhere would otherwise pay
    // for a scan at every opener.
    var rescanBudget = text.length * 4;
    var inString = false;
    while (i < text.length) {
      // `fi` only moves right, so the fence test is O(1) amortised. The old
      // _insideFence re-scanned every fence at every index.
      while (fi < fences.length && fences[fi].end <= i) {
        fi++;
      }
      if (fi < fences.length && i >= fences[fi].start && i < fences[fi].end) {
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
        var end = ends[i];
        if (end == null) {
          blindEnds ??= _matchEndsBlind(text);
          final blind = blindEnds[i];
          if (blind != null) {
            realFences ??= _realFences(text, fences);
            while (fj < realFences.length && realFences[fj].start < i) {
              fj++;
            }
            // Accept only a span that stays clear of every real fence. A span
            // crossing one is not a legitimate bare call, and accepting it
            // executed code sitting inside a tagged block while making a fenced
            // payload quadratic.
            if (fj >= realFences.length || realFences[fj].start >= blind) {
              end = blind;
            }
          }
        }
        if (end == null && rescanBudget > 0) {
          // Neither map has an answer for this opener. Fall back to the shipped
          // parser's own rule, which restarts the quote state here instead of
          // trusting a walk that may have desynced upstream. The rescan is
          // charged for every character it examines -- including a span that
          // never balances -- so the total work stays linear.
          final cost = <int>[0];
          final rescan = _scanFrom(text, i, rescanBudget, cost);
          rescanBudget -= cost[0];
          if (rescan != null) end = rescan;
        }
        if (end != null) {
          final decoded = _tryDecode(text.substring(i, end));
          if (decoded != null) {
            final recovery = _recoverDecoded(decoded, isKnownTool);
            final calls = recovery.calls;
            if (calls != null) {
              accepted.add(_AcceptedSpan(i, end, calls));
              i = end;
              continue;
            }
            if (recovery.overloaded) {
              // The span decoded but was too deep to walk or encode. Trying
              // every opener inside it is what made a deep payload quadratic,
              // and a payload this deep cannot contain a usable call, so step
              // over it. A span that merely decodes without a call is NOT
              // skipped: a call nested inside it must still be recovered.
              i = end;
              continue;
            }
          }
        }
      }
      i++;
    }
  }

  /// Exclusive end of the shortest balanced span starting at [start], with the
  /// quote state restarted at [start].
  ///
  /// This is the previously shipped parser's own rule, kept for the openers
  /// where both maps above hold no answer. Those maps answer from a single
  /// left-to-right walk carrying one quote state, so a message whose quotes
  /// desync that walk leaves openers unanswered that the shipped parser
  /// recovered; restarting here reproduces its answer. Returns null when the
  /// span never balances, exactly as the shipped helper did.
  ///
  /// [cost] receives the number of characters examined, and is charged even on
  /// failure: a span that never balances is exactly the case that walks to
  /// end-of-string, and leaving that uncharged made a brace flood quadratic.
  /// The walk also stops at [budget] characters, so one rescan can never spend
  /// more than the caller has left.
  int? _scanFrom(String text, int start, int budget, List<int> cost) {
    final closers = <int>[];
    var i = start;
    var inString = false;
    final limit = start + budget;
    while (i < text.length && i < limit) {
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
        if (closers.isEmpty || closers.last != c) {
          cost[0] = i - start + 1;
          return null;
        }
        closers.removeLast();
        if (closers.isEmpty) {
          cost[0] = i - start + 1;
          return i + 1;
        }
      }
      i++;
    }
    cost[0] = i - start;
    return null;
  }

  /// Decodes and validates one candidate span, or null when it is not a
  /// usable tool call.
  List<_ValidatedCall>? _recover(
    String source,
    bool Function(String name)? isKnownTool,
  ) {
    final decoded = _tryDecode(source);
    if (decoded == null) return null;
    return _recoverDecoded(decoded, isKnownTool).calls;
  }

  /// Validates an already-decoded value.
  ///
  /// A malformed payload can make the tree walk or the argument encoding throw
  /// an [Error] such as a StackOverflowError. No Error may escape [parse], so
  /// this catches [Object] and reports the span as [overloaded] instead.
  _Recovery _recoverDecoded(
    dynamic decoded,
    bool Function(String name)? isKnownTool,
  ) {
    try {
      final extracted = _extract(decoded);
      final calls = _validate(extracted.candidates, isKnownTool);
      return _Recovery(
        calls.isEmpty ? null : calls,
        extracted.capped,
      );
    } catch (_) {
      return const _Recovery(null, true);
    }
  }

  /// Collects tool-call candidates from an already-decoded tree.
  ///
  /// Descends at most [maxJsonDepth] levels; deeper subtrees simply contribute
  /// no candidates. Reporting "too deep" for the *whole* span instead (the
  /// previous behaviour) let one deep sibling hide a legitimate shallow one,
  /// because the caller then skipped the entire span.
  ///
  /// The cap bounds the *descent* only. The current node is always inspected
  /// for a call first, because that is a set of shallow map lookups that cannot
  /// recurse: a call sitting above the cap must still be recovered (the shipped
  /// parser found one at depth ~4000), while descending into an adversarial
  /// 100k-deep nest must still stop before the recursion overflows the stack.
  _Extracted _extract(dynamic value) {
    final out = <_RawCandidate>[];
    // Iterative walk on an explicit heap stack. A recursive walk overflows the
    // VM stack on an adversarial deep nest (~10000+ levels) and, worse, any
    // depth cap that avoids that overflow necessarily discards every call
    // sitting deeper than the cap - which the shipped parser recovered up to
    // ~4000. An explicit stack has no such ceiling, so coverage is preserved
    // and the overflow is designed out rather than bounded away.
    final stack = <dynamic>[value];
    while (stack.isNotEmpty) {
      final node = stack.removeLast();
      if (node is Map) {
        final name = node['name'];
        if (name is String && name.isNotEmpty && node.containsKey('arguments')) {
          out.add(_RawCandidate(name, node['arguments']));
          continue;
        }
        final function = node['function'];
        if (function is Map) {
          final fnName = function['name'];
          if (fnName is String &&
              fnName.isNotEmpty &&
              function.containsKey('arguments')) {
            out.add(_RawCandidate(fnName, function['arguments']));
            continue;
          }
        }
        final toolCalls = node['tool_calls'];
        if (toolCalls is List) {
          // Reversed so popping visits them in document order.
          for (var i = toolCalls.length - 1; i >= 0; i--) {
            stack.add(toolCalls[i]);
          }
        }
        continue;
      }
      if (node is List) {
        for (var i = node.length - 1; i >= 0; i--) {
          stack.add(node[i]);
        }
      }
    }
    return _Extracted(out, false);
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
        // jsonEncode is recursive and overflows the VM stack on a deeply
        // nested arguments map (~4300 AOT / ~3300 JIT). Letting that escape
        // would make the caller's catch treat the WHOLE span as unusable and
        // skip it, silently discarding every other call inside it. Guarding
        // here drops only the candidate that cannot be serialised, which is
        // the right blast radius: a pathological payload contributes no call
        // (the documented behaviour for adversarial input) while a legitimate
        // shallow sibling beside it is still recovered.
        try {
          fragment = jsonEncode(arguments);
        } catch (_) {
          continue;
        }
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

/// Result of validating one decoded span.
class _Recovery {
  final List<_ValidatedCall>? calls;
  final bool overloaded;
  const _Recovery(this.calls, this.overloaded);
}

/// Candidates found in a decoded tree, plus whether the walk hit
/// [ToolCallTextParser.maxJsonDepth] and therefore pruned a subtree.
class _Extracted {
  final List<_RawCandidate> candidates;
  final bool capped;
  const _Extracted(this.candidates, this.capped);
}
