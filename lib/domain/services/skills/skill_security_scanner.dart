import 'dart:convert';

import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill_scan.dart';

/// Scans imported skills for prompt-injection payloads and unknown tools.
@lazySingleton
class SkillSecurityScanner {
  static const String patternIgnorePreviousInstructions =
      'ignore_previous_instructions';
  static const String patternDisregardSystemPrompt = 'disregard_system_prompt';
  static const String patternExfiltrate = 'exfiltrate';
  static const String patternSendCredentialsOut = 'send_credentials_out';
  static const String patternRevealSystemPrompt = 'reveal_system_prompt';
  static const String patternDoNotTellUser = 'do_not_tell_user';
  static const String patternRoleOverride = 'role_override';
  static const String patternJailbreak = 'jailbreak';
  static const String patternNewInstructionsHeader = 'new_instructions_header';
  static const String patternChatmlDelimiters = 'chatml_delimiters';
  static const String patternSecretHarvest = 'secret_harvest';
  static const String patternHiddenHtmlInstructions =
      'hidden_html_instructions';
  static const String patternBase64Blob = 'base64_blob';
  static const String patternBase64EncodedPayload = 'base64_encoded_payload';

  static final RegExp _formatCharacters = RegExp(
    '[\u00ad\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff]',
  );
  static final RegExp _markdownDelimiters = RegExp(
    r'(?<!\w)[*_~`]+|[*_~`]+(?!\w)',
  );
  static final RegExp _whitespaceRuns = RegExp(r'\s+');
  static final RegExp _base64Candidate = RegExp(r'[A-Za-z0-9+/]{40,}={0,2}');

  /// Largest base64 candidate that is decoded; longer runs are skipped so a
  /// hostile document cannot force a huge decode (decode bomb).
  static const int _maxBase64CandidateLength = 64 * 1024;

  /// Verbs that turn an override phrase into an instruction.
  static const String _directiveVerb =
      r'(?:obey(?:ing|s)?|follow(?:ing|s)?|do|execute|apply|'
      r'comply\s+with|act\s+on)';

  /// Objects that complete a directive, such as `the text below` or `me`.
  static const String _directiveObject =
      r'(?:the\s+text\s+below|what\s+follows|these\s+rules|this\s+text|'
      r'the\s+following|me)';

  /// A directive verb plus an object, tolerating punctuation between them.
  static const String _directiveVerbPhrase =
      '(?:$_directiveVerb\\b[\\s,]*'
      '(?:$_directiveObject|'
      '(?:the\\s+|this\\s+|these\\s+|what\\s+|a\\s+|an\\s+|your\\s+|my\\s+)'
      '\\w+))';

  /// Requires an override verb phrase to read as an instruction: followed by
  /// end of sentence/line, a punctuation stop, `now`, a heading or list
  /// marker, `and`/`then` plus a following word, a directive verb plus
  /// object, or a "with the following" / "as follows" continuation. A bare
  /// conditional continuation (`when ...`, `if ...`, `only when ...`) never
  /// matches, which is what keeps prose about ignoring things benign.
  static const String _directiveTail =
      '(?=\\s*(?:[:.!?;]|\$|now\\b|'
      '#\\s+\\w+|'
      '\\d+[.)]\\s+$_directiveVerbPhrase|'
      '[\\s,;:\\-]*(?:and|then)[\\s,;:\\-]*\\w+|'
      'with\\s+$_directiveObject|'
      'using\\s+(?:the\\s+text\\s+below|the\\s+following|this\\s+text)|'
      'as\\s+follows|'
      '[\\s,;:\\-]*$_directiveVerbPhrase))';

  static final List<_ScanPattern> _patterns = [
    _ScanPattern(
      patternIgnorePreviousInstructions,
      'Attempts to override prior instructions',
      SkillScanSeverity.critical,
      r'(ignore|forget|discard|disregard)\s+'
          r'(all\s+|the\s+|your\s+|any\s+|everything\s+)*'
          r'(previous|prior|above|earlier|preceding)\s+'
          r'(instruction|prompt|rule|message|direction|command|guideline)?s?'
          '$_directiveTail',
      negatable: true,
    ),
    _ScanPattern(
      patternDisregardSystemPrompt,
      'Attempts to disregard the system prompt',
      SkillScanSeverity.critical,
      r'(disregard|override)\s+(the\s+)?'
          r'(system\s+prompt|previous|prior|above|earlier)'
          r'\s*(instruction|prompt|rule|message|direction|command|guideline)?s?'
          '$_directiveTail',
      negatable: true,
    ),
    _ScanPattern(
      patternExfiltrate,
      'Attempts to exfiltrate data',
      SkillScanSeverity.critical,
      r'exfiltrat',
    ),
    _ScanPattern(
      patternSendCredentialsOut,
      'Attempts to send credentials to an external endpoint',
      SkillScanSeverity.critical,
      r'(send|post|upload|forward|transmit|leak)\s.{0,60}'
          r'(https?://|webhook|api[_ ]?key|access[_ ]?token|credential|password)',
    ),
    _ScanPattern(
      patternRevealSystemPrompt,
      'Attempts to reveal the system prompt',
      SkillScanSeverity.high,
      r'(reveal|print|output|repeat|show|display)\s.{0,30}'
          r'(system\s+prompt|your\s+instruction|hidden\s+prompt)',
    ),
    _ScanPattern(
      patternDoNotTellUser,
      'Instructs the agent to withhold information from the user',
      SkillScanSeverity.high,
      r"(do\s+not|don't|never)\s+(tell|inform|mention|notify|alert)"
          r'\s+(the\s+)?user',
    ),
    _ScanPattern(
      patternRoleOverride,
      'Attempts to override the agent role',
      SkillScanSeverity.high,
      r'you\s+are\s+(now|no\s+longer)\s',
    ),
    _ScanPattern(
      patternJailbreak,
      'Contains a jailbreak directive',
      SkillScanSeverity.high,
      r'(jailbreak|dan\s+mode|developer\s+mode\s+enabled|unrestricted\s+mode'
          r'|act\s+as\s+an?\s+unrestricted)',
    ),
    _ScanPattern(
      patternNewInstructionsHeader,
      'Declares a new instructions block',
      SkillScanSeverity.high,
      r'new\s+(system\s+)?instruction(s)?\s*:',
    ),
    _ScanPattern(
      patternChatmlDelimiters,
      'Contains chat markup delimiters',
      SkillScanSeverity.critical,
      r'<\|im_start\|>|<\|im_end\|>|\[\/?INST\]|<<\/?SYS>>',
    ),
    _ScanPattern(
      patternSecretHarvest,
      'Attempts to harvest secrets',
      SkillScanSeverity.high,
      r'(api[_ ]?key|private[_ ]key|seed\s+phrase|password|otp|'
          r'one[- ]time\s+code|access[_ ]token)s?\b.{0,40}'
          r'(read|extract|collect|gather|harvest|send|upload)',
    ),
    _ScanPattern(
      patternHiddenHtmlInstructions,
      'Hides instructions inside HTML comments',
      SkillScanSeverity.high,
      r'<!--[\s\S]{0,400}(ignore|instruction|system\s+prompt)',
    ),
    _ScanPattern(
      patternBase64Blob,
      'Contains a large base64 blob',
      SkillScanSeverity.high,
      r'[A-Za-z0-9+\/]{120,}={0,2}',
    ),
  ];

  /// Scans [skill] for prompt-injection payloads and for tool requests
  /// that are not in [registeredToolNames].
  ///
  /// Invariant: the scan surface must cover every [Skill] field that
  /// `SkillsRegistryService.buildSystemPrompt()` injects into the system
  /// prompt (name, category, version, description, instructions, prompts)
  /// plus [Skill.author] for defence in depth. Tools are validated
  /// separately against [registeredToolNames].
  SkillScanResult scan({
    required Skill skill,
    required Set<String> registeredToolNames,
  }) {
    final surface = [
      skill.instructions,
      skill.description,
      ...skill.prompts,
      skill.name,
      skill.category,
      skill.version,
      skill.author,
    ];
    final text = _normalise(surface.join('\n'));
    final findings = <SkillScanFinding>[];
    for (final pattern in _patterns) {
      final match = pattern.firstNonNegatedMatch(text);
      if (match != null) {
        final raw = match.group(0) ?? '';
        findings.add(
          SkillScanFinding(
            patternId: pattern.id,
            description: pattern.description,
            severity: pattern.severity,
            excerpt: raw.length > 120 ? raw.substring(0, 120) : raw,
          ),
        );
      }
    }
    final encodedFinding = _scanBase64Payloads(surface);
    if (encodedFinding != null) {
      findings.add(encodedFinding);
    }
    final unknownTools = <String>[];
    for (final name in skill.tools) {
      if (!registeredToolNames.contains(name) && !unknownTools.contains(name)) {
        unknownTools.add(name);
      }
    }
    return SkillScanResult(findings: findings, unknownTools: unknownTools);
  }

  /// Decodes base64-looking runs from [surface] and reports at most one
  /// critical finding when a decoded payload matches an injection pattern.
  ///
  /// Two passes run over the case-preserving [surface]:
  /// 1. the original text, so an unwrapped blob keeps its exact excerpt;
  /// 2. a "squeezed" view with whitespace, format characters, and markdown
  ///    delimiters removed and the base64url alphabet mapped, so line
  ///    wrapping, indentation, inserted spaces, and inserted format
  ///    characters cannot split a payload into undecodable runs.
  ///
  /// Each field is scanned separately so squeezing one field cannot glue
  /// unrelated fields together into a bogus candidate.
  static SkillScanFinding? _scanBase64Payloads(List<String> surface) {
    for (final field in surface) {
      final direct = _findEncodedPayloadIn(field, trimWhitespace: true);
      if (direct != null) {
        return direct;
      }
      final squeezed = _findEncodedPayloadIn(
        _squeeze(field),
        allowPrintableTail: true,
      );
      if (squeezed != null) {
        return squeezed;
      }
    }
    return null;
  }

  static SkillScanFinding? _findEncodedPayloadIn(
    String text, {
    bool trimWhitespace = false,
    bool allowPrintableTail = false,
  }) {
    for (final candidate in _base64Candidate.allMatches(text)) {
      final run = candidate.group(0)!;
      if (run.length > _maxBase64CandidateLength) {
        continue;
      }
      final finding = _decodeAndMatch(
        run,
        trimWhitespace: trimWhitespace,
        allowPrintableTail: allowPrintableTail,
      );
      if (finding != null) {
        return finding;
      }
    }
    return null;
  }

  /// Decodes [run] at each of the four base64 phases and returns a finding
  /// when any decoding yields an injection payload. The phase offsets make
  /// the match independent of how many characters precede the payload.
  ///
  /// When squeezing glued ordinary text after the payload, the decoded tail
  /// stops being printable; with [allowPrintableTail] the printable prefix
  /// of each decoding is matched, so such a tail cannot hide the payload.
  static SkillScanFinding? _decodeAndMatch(
    String run, {
    bool trimWhitespace = false,
    bool allowPrintableTail = false,
  }) {
    for (var phase = 0; phase < 4; phase++) {
      var candidate = run.substring(phase);
      if (trimWhitespace) {
        candidate = candidate.replaceAll(_whitespaceRuns, '');
      }
      final bytes = _decodeBase64Bytes(candidate);
      if (bytes == null) {
        continue;
      }
      var end = bytes.length;
      if (allowPrintableTail) {
        end = 0;
        while (end < bytes.length && _isPrintableByte(bytes[end])) {
          end++;
        }
      } else if (!bytes.every(_isPrintableByte)) {
        continue;
      }
      if (end < 8) {
        continue;
      }
      final finding = _matchDecoded(
        String.fromCharCodes(bytes.sublist(0, end)),
      );
      if (finding != null) {
        return finding;
      }
    }
    return null;
  }

  static SkillScanFinding? _matchDecoded(String decodedText) {
    final normalised = _normalise(decodedText);
    for (final pattern in _patterns) {
      if (pattern.firstNonNegatedMatch(normalised) == null) {
        continue;
      }
      return SkillScanFinding(
        patternId: patternBase64EncodedPayload,
        description: 'Contains a base64-encoded instruction payload',
        severity: SkillScanSeverity.critical,
        excerpt: normalised.length > 120
            ? normalised.substring(0, 120)
            : normalised,
      );
    }
    return null;
  }

  /// Case-preserving view of [value] with whitespace, format characters,
  /// markdown delimiters, and base64url alphabet characters removed or
  /// mapped, so wrapped or split payloads become one contiguous run.
  static String _squeeze(String value) {
    var result = value.replaceAll(_formatCharacters, '');
    result = result.replaceAll(_markdownDelimiters, '');
    result = result.replaceAll(_whitespaceRuns, '');
    return result.replaceAll('-', '+').replaceAll('_', '/');
  }

  static List<int>? _decodeBase64Bytes(String candidate) {
    final stripped = candidate.replaceAll(_whitespaceRuns, '');
    final remainder = stripped.length % 4;
    final padded = remainder == 0
        ? stripped
        : stripped.padRight(stripped.length + (4 - remainder), '=');
    try {
      return base64Decode(padded);
    } catch (_) {
      return null;
    }
  }

  static bool _isPrintableByte(int byte) =>
      byte == 0x09 ||
      byte == 0x0a ||
      byte == 0x0d ||
      (byte >= 0x20 && byte <= 0x7e);

  /// Returns [skill] with the import policy applied: a Tier 3 (HITL)
  /// skill can never be enabled by an import, and every imported skill
  /// is marked as community.
  Skill applyImportPolicy(Skill skill) {
    final rank = _parseTierRank(skill.tier);
    final autoEnableable = rank == 1 || rank == 2;
    return skill.copyWith(
      isEnabled: autoEnableable ? skill.isEnabled : false,
      isCommunity: true,
    );
  }

  static final RegExp _tierNoise = RegExp(r'[^a-z0-9 -]');
  static final RegExp _tierSeparators = RegExp(r'[ -]+');

  static const Map<String, int> _tierWordRanks = {
    'one': 1,
    'i': 1,
    '1': 1,
    'two': 2,
    'ii': 2,
    '2': 2,
    'three': 3,
    'iii': 3,
    '3': 3,
    'four': 4,
    'iv': 4,
    '4': 4,
  };

  static const Map<String, String> _tierUnicodeNumerals = {
    'Ⅰ': 'i',
    'ⅰ': 'i',
    'Ⅱ': 'ii',
    'ⅱ': 'ii',
    'Ⅲ': 'iii',
    'ⅲ': 'iii',
    'Ⅳ': 'iv',
    'ⅳ': 'iv',
  };

  static int? _parseTierRank(String tier) {
    final normalised = _normaliseTier(tier);
    if (normalised.isEmpty) {
      return null;
    }
    int? rank;
    for (final token in normalised.split(_tierSeparators)) {
      final tokenRank = _rankOfTierToken(token);
      if (tokenRank == null) {
        continue;
      }
      if (tokenRank > 2) {
        return tokenRank;
      }
      rank ??= tokenRank;
    }
    return rank;
  }

  static String _normaliseTier(String tier) {
    final buffer = StringBuffer();
    for (final rune in tier.toLowerCase().runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        buffer.writeCharCode(0x30 + rune - 0x0660);
      } else if (rune >= 0x06f0 && rune <= 0x06f9) {
        buffer.writeCharCode(0x30 + rune - 0x06f0);
      } else if (rune >= 0xff10 && rune <= 0xff19) {
        buffer.writeCharCode(0x30 + rune - 0xff10);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    var normalised = buffer.toString();
    for (final entry in _tierUnicodeNumerals.entries) {
      normalised = normalised.replaceAll(entry.key, entry.value);
    }
    return normalised.replaceAll(_tierNoise, '');
  }

  static int? _rankOfTierToken(String token) {
    if (token.isEmpty) {
      return null;
    }
    final direct = _tierWordRanks[token];
    if (direct != null) {
      return direct;
    }
    if (token.startsWith('tier')) {
      return _rankOfTierToken(token.substring(4));
    }
    if (token.startsWith('t')) {
      return _rankOfTierToken(token.substring(1));
    }
    final digit = token.codeUnitAt(0) - 0x30;
    if (digit >= 0 && digit <= 9) {
      final rest = token.substring(1);
      if (rest.isEmpty || rest == 'hitl') {
        return digit;
      }
    }
    return null;
  }

  static String _normalise(String value) {
    var result = value.replaceAll(_formatCharacters, '');
    result = result.toLowerCase();
    result = result.replaceAll(_markdownDelimiters, ' ');
    return result.replaceAll(_whitespaceRuns, ' ');
  }
}

class _ScanPattern {
  final String id;
  final String description;
  final SkillScanSeverity severity;
  final RegExp regexp;
  final bool negatable;

  _ScanPattern(
    this.id,
    this.description,
    this.severity,
    String source, {
    this.negatable = false,
  }) : regexp = RegExp(source, multiLine: true, caseSensitive: false);

  /// First match of [regexp] in [text] that is not preceded by a negation
  /// such as `do not` or `never`. Non-negatable patterns return the first
  /// match unconditionally.
  Match? firstNonNegatedMatch(String text) {
    for (final match in regexp.allMatches(text)) {
      if (!negatable || !_isNegated(text, match.start)) return match;
    }
    return null;
  }

  static bool _isNegated(String text, int start) {
    final windowStart = start - 40 < 0 ? 0 : start - 40;
    return _negationPrefix.hasMatch(text.substring(windowStart, start));
  }

  /// Matches a negated override verb phrase, such as `do not ignore`,
  /// `never forget`, or `do not ever ignore`. At most one word may sit
  /// between the negator and the verb.
  static final RegExp _negationPrefix = RegExp(
    r"(?:do\s+not|don't|does\s+not|doesn't|never|must\s+not|mustn't|"
    r"should\s+not|shouldn't|cannot|can't|avoid|no\s+need\s+to)"
    r'\s+(?:\w+\s+){0,1}$',
  );
}
