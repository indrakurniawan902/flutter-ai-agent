import 'package:equatable/equatable.dart';

/// Binds an NFC card UID to a prompt string sent to the agent when tapped.
class NfcTagPromptBinding extends Equatable {
  /// Lowercase hex, no separators.
  final String cardUid;

  /// The text to send to the agent when this UID is tapped.
  final String prompt;

  /// User-friendly name, optional.
  final String? label;

  final DateTime createdAt;

  const NfcTagPromptBinding({
    required this.cardUid,
    required this.prompt,
    this.label,
    required this.createdAt,
  });

  NfcTagPromptBinding copyWith({
    String? cardUid,
    String? prompt,
    String? label,
    DateTime? createdAt,
  }) =>
      NfcTagPromptBinding(
        cardUid: cardUid ?? this.cardUid,
        prompt: prompt ?? this.prompt,
        label: label ?? this.label,
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toJson() => {
        'cardUid': cardUid,
        'prompt': prompt,
        if (label != null) 'label': label,
        'createdAt': createdAt.toIso8601String(),
      };

  factory NfcTagPromptBinding.fromJson(Map<String, dynamic> json) =>
      NfcTagPromptBinding(
        cardUid: json['cardUid'] as String,
        prompt: json['prompt'] as String,
        label: json['label'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  @override
  List<Object?> get props => [cardUid, prompt, label, createdAt];
}
