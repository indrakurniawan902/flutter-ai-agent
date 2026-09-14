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

  static final RegExp _zeroWidth = RegExp('[\u200b-\u200d\ufeff]');
  static final RegExp _whitespaceRuns = RegExp(r'\s+');

  static final List<_ScanPattern> _patterns = [
    _ScanPattern(
      patternIgnorePreviousInstructions,
      'Attempts to override prior instructions',
      SkillScanSeverity.critical,
      r'ignore\s+(all\s+)?(the\s+)?(previous|prior|above|earlier)\s+'
          r'(instruction|prompt|rule|message)',
    ),
    _ScanPattern(
      patternDisregardSystemPrompt,
      'Attempts to disregard the system prompt',
      SkillScanSeverity.critical,
      r'disregard\s+(the\s+)?(system\s+prompt|previous|prior|above|earlier)'
          r'\s*(instruction|prompt|rule|message)?',
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
      SkillScanSeverity.medium,
      r'<!--[\s\S]{0,400}(ignore|instruction|system\s+prompt)',
    ),
    _ScanPattern(
      patternBase64Blob,
      'Contains a large base64 blob',
      SkillScanSeverity.medium,
      r'[A-Za-z0-9+\/]{200,}={0,2}',
    ),
  ];

  /// Scans [skill] for prompt-injection payloads and for tool requests
  /// that are not in [registeredToolNames].
  SkillScanResult scan({
    required Skill skill,
    required Set<String> registeredToolNames,
  }) {
    final surface = [
      skill.instructions,
      skill.description,
      ...skill.prompts,
      skill.name,
    ].join('\n');
    final text = _normalise(surface);
    final findings = <SkillScanFinding>[];
    for (final pattern in _patterns) {
      final match = pattern.regexp.firstMatch(text);
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
    final unknownTools = <String>[];
    for (final name in skill.tools) {
      if (!registeredToolNames.contains(name) && !unknownTools.contains(name)) {
        unknownTools.add(name);
      }
    }
    return SkillScanResult(findings: findings, unknownTools: unknownTools);
  }

  /// Returns [skill] with the import policy applied: a Tier 3 (HITL)
  /// skill can never be enabled by an import, and every imported skill
  /// is marked as community.
  Skill applyImportPolicy(Skill skill) {
    final isTier3 = skill.tier.toLowerCase().contains('tier 3');
    return skill.copyWith(
      isEnabled: isTier3 ? false : skill.isEnabled,
      isCommunity: true,
    );
  }

  static String _normalise(String value) {
    var result = value.replaceAll(_zeroWidth, '');
    result = result.toLowerCase();
    return result.replaceAll(_whitespaceRuns, ' ');
  }
}

class _ScanPattern {
  final String id;
  final String description;
  final SkillScanSeverity severity;
  final RegExp regexp;

  _ScanPattern(this.id, this.description, this.severity, String source)
    : regexp = RegExp(source, multiLine: false, caseSensitive: false);
}
