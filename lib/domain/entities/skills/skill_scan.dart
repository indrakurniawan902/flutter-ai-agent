import 'package:equatable/equatable.dart';

/// Severity of a prompt-injection scan finding.
enum SkillScanSeverity { critical, high, medium }

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

  /// Any finding with a severity other than medium.
  bool get hasBlockingFindings =>
      findings.any((f) => f.severity != SkillScanSeverity.medium);

  /// Whether the skill requests tools missing from the build.
  bool get hasUnknownTools => unknownTools.isNotEmpty;

  /// Whether the import must be refused.
  bool get isRejected => hasBlockingFindings || hasUnknownTools;

  /// Whether the skill passed the scan.
  bool get isClean => !isRejected;

  /// One human-readable sentence naming blocking ids and unknown tools.
  String? get rejectionReason {
    if (isClean) return null;
    final parts = <String>[];
    if (hasBlockingFindings) {
      final ids = findings
          .where((f) => f.severity != SkillScanSeverity.medium)
          .map((f) => f.patternId)
          .toList();
      parts.add('Blocked by prompt-injection scan: ${ids.join(', ')}');
    }
    if (hasUnknownTools) {
      parts.add(
        'Requests tools that are not registered in this build: '
        '${unknownTools.join(', ')}',
      );
    }
    return parts.join('. ');
  }

  @override
  List<Object?> get props => [findings, unknownTools];
}
