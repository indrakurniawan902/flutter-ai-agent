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

  static final RegExp _formatCharacters = RegExp(
    '[\u00ad\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff]',
  );
  static final RegExp _markdownDelimiters = RegExp(
    r'(?<!\w)[*_~`]+|[*_~`]+(?!\w)',
  );
  static final RegExp _whitespaceRuns = RegExp(r'\s+');

  /// Requires the override phrase to read as an instruction: it must end the
  /// sentence/line, be followed by a punctuation stop, or continue with a
  /// directive. A bare conditional continuation (`when ...`, `if ...`,
  /// `only when ...`) never matches, which keeps prose about ignoring things
  /// out of the advisory list.
  ///
  /// The leading class absorbs the separator because `_normalise` collapses
  /// newlines, so a line-terminated imperative reaches this lookahead as
  /// `... instructions do the task.`
  static const String _directiveTail =
      r'(?=[\s\-–—,;:]*(?:[.!?]|$|(?:and|then)\b|'
      r'with\s+(?:the\s+text\s+below|the\s+following|this\s+text)|'
      r'using\s+(?:the\s+text\s+below|the\s+following|this\s+text)|'
      r'as\s+follows|'
      r'(?:obey|follow|do|execute|apply|act\s+on)\b))';

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
  ];

  /// Scans [skill] for prompt-injection payloads and for tool requests
  /// that are not in [registeredToolNames].
  ///
  /// Invariant: the scan surface must cover every [Skill] field that
  /// `SkillsRegistryService.buildSystemPrompt()` injects into the system
  /// prompt (name, category, version, description, instructions, prompts)
  /// plus [Skill.author] for defence in depth. Tools are validated
  /// separately against [registeredToolNames].
  ///
  /// Findings are ADVISORY: they are reported to the user and never block an
  /// import. The only rejection path is `unknownTools`.
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
    final findings = scanText(surface.join('\n'));
    final unknownTools = <String>[];
    for (final name in skill.tools) {
      if (!registeredToolNames.contains(name) && !unknownTools.contains(name)) {
        unknownTools.add(name);
      }
    }
    return SkillScanResult(findings: findings, unknownTools: unknownTools);
  }

  /// Scans raw [text] (any untrusted surface: screen content, notifications,
  /// fetched pages) with the same pattern list used for skill imports.
  /// Findings are ADVISORY: callers must never block on them.
  List<SkillScanFinding> scanText(String text) {
    if (text.trim().isEmpty) return const [];
    final normalised = _normalise(text);
    final findings = <SkillScanFinding>[];
    for (final pattern in _patterns) {
      final match = pattern.firstNonNegatedMatch(normalised);
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
    return findings;
  }

  /// Community skills are never enabled on import: the user opts in explicitly.
  /// The declared tier is attacker-controlled text and is display-only.
  Skill applyImportPolicy(Skill skill) =>
      skill.copyWith(isEnabled: false, isCommunity: true);

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
