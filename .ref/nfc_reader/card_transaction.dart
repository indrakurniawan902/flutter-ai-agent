enum TransactionType { debit, credit, unknown }

enum TransactionSource { nfc, manual, unknown }

class CardTransaction {
  const CardTransaction({
    required this.id,
    required this.cardId,
    required this.cardBrand,
    required this.cardType,
    required this.timestamp,
    required this.type,
    required this.amount,
    required this.source,
    this.balanceAfter,
    this.label,
  });

  final String id;
  final String cardId;
  final String cardBrand;
  final String cardType;
  final DateTime timestamp;
  final TransactionType type;
  final int amount;
  final int? balanceAfter;
  final TransactionSource source;
  final String? label;
}
