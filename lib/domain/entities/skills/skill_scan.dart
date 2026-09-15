import 'package:equatable/equatable.dart';

/// Severity of a prompt-injection scan finding.
enum SkillScanSeverity {
  critical,
  high,

  /// Informational tier. No current pattern emits `medium`; findings are
  /// advisory, so the tier is display-only for now.
  medium,
}

/// A single prompt-injection pattern match.
class SkillScanFinding extends Equatable {
  final String patternId;
  final String description;
  final SkillScanSeverity severity;
  final String? excerpt;

  const SkillScanFinding({
    required this.patternId,
    required this.description,
    required this.severity,
    this.excerpt,
  });

  @override
  List<Object?> get props => [patternId, description, severity, excerpt];
}

/// Result of scanning a skill for prompt-injection and unknown tools.
class SkillScanResult extends Equatable {
  final List<SkillScanFinding> findings;
  final List<String> unknownTools;

  const SkillScanResult({
    this.findings = const [],
    this.unknownTools = const [],
  });

  /// Whether the skill requests tools missing from the build. This is the ONLY
  /// rejection path: a tool that does not exist in this build cannot be called,
  /// however the payload is encoded.
  bool get hasUnknownTools => unknownTools.isNotEmpty;

  /// Whether the import must be refused.
  bool get isRejected => hasUnknownTools;

  /// Whether the skill passed the structural gate.
  bool get isClean => !isRejected;

  /// One human-readable sentence naming the unknown tools, or null when none.
  String? get rejectionReason {
    if (!hasUnknownTools) return null;
    return 'Requests tools that are not registered in this build: '
        '${unknownTools.join(', ')}';
  }

  @override
  List<Object?> get props => [findings, unknownTools];
}
