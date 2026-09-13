class CardBalance {
  const CardBalance({
    required this.amount,
    required this.currencyCode,
    required this.readAt,
    required this.source,
  });

  final int amount;
  final String currencyCode;
  final DateTime readAt;

  /// Must be `nfc` when the amount came from a real card read.
  final String source;

  bool get isFromNfc => source == 'nfc';
}
