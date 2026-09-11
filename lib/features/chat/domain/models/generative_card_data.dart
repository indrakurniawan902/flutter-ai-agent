import 'package:equatable/equatable.dart';

/// Data model representing an Action Confirmation Micro-UI card.
class ActionConfirmationData extends Equatable {
  final String title;
  final String message;
  final Map<String, dynamic>? parameters;
  final String primaryActionLabel;
  final String secondaryActionLabel;
  final String? tierLabel;
  final bool isConfirmed;
  final bool isDismissed;

  const ActionConfirmationData({
    required this.title,
    required this.message,
    this.parameters,
    this.primaryActionLabel = 'Confirm',
    this.secondaryActionLabel = 'Cancel',
    this.tierLabel,
    this.isConfirmed = false,
    this.isDismissed = false,
  });

  ActionConfirmationData copyWith({
    String? title,
    String? message,
    Map<String, dynamic>? parameters,
    String? primaryActionLabel,
    String? secondaryActionLabel,
    String? tierLabel,
    bool? isConfirmed,
    bool? isDismissed,
  }) {
    return ActionConfirmationData(
      title: title ?? this.title,
      message: message ?? this.message,
      parameters: parameters ?? this.parameters,
      primaryActionLabel: primaryActionLabel ?? this.primaryActionLabel,
      secondaryActionLabel: secondaryActionLabel ?? this.secondaryActionLabel,
      tierLabel: tierLabel ?? this.tierLabel,
      isConfirmed: isConfirmed ?? this.isConfirmed,
      isDismissed: isDismissed ?? this.isDismissed,
    );
  }

  @override
  List<Object?> get props => [
        title,
        message,
        parameters,
        primaryActionLabel,
        secondaryActionLabel,
        tierLabel,
        isConfirmed,
        isDismissed,
      ];
}

/// Key-value metric or highlight item in a Summary Card.
class SummaryMetricItem extends Equatable {
  final String label;
  final String value;

  const SummaryMetricItem({
    required this.label,
    required this.value,
  });

  @override
  List<Object?> get props => [label, value];
}

/// Data model representing a Summary Micro-UI card with copy and share capabilities.
class SummaryCardData extends Equatable {
  final String title;
  final String summaryText;
  final List<SummaryMetricItem> items;
  final Map<String, dynamic>? metadata;

  const SummaryCardData({
    required this.title,
    required this.summaryText,
    this.items = const [],
    this.metadata,
  });

  SummaryCardData copyWith({
    String? title,
    String? summaryText,
    List<SummaryMetricItem>? items,
    Map<String, dynamic>? metadata,
  }) {
    return SummaryCardData(
      title: title ?? this.title,
      summaryText: summaryText ?? this.summaryText,
      items: items ?? this.items,
      metadata: metadata ?? this.metadata,
    );
  }

  @override
  List<Object?> get props => [title, summaryText, items, metadata];
}
