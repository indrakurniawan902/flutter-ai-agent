import 'package:nfc_card_reader/features/scanner/domain/entities/card_balance.dart';
import 'package:nfc_card_reader/features/scanner/domain/entities/card_transaction.dart';
import 'package:nfc_card_reader/features/scanner/domain/entities/nfc_card.dart';

sealed class CardReadResult {
  const CardReadResult();
}

final class CardReadSuccess extends CardReadResult {
  const CardReadSuccess({
    required this.cardType,
    required this.brand,
    required this.nfcCard,
    required this.balance,
    this.cardNumber,
    this.transactions = const [],
    this.message = 'Saldo berhasil dibaca dari kartu',
  });

  final String cardType;
  final CardBrand brand;
  final NfcCard nfcCard;
  final CardBalance balance;
  final String? cardNumber;
  final List<CardTransaction> transactions;
  final String message;
}

final class CardPartiallyRead extends CardReadResult {
  const CardPartiallyRead({
    required this.cardType,
    required this.brand,
    required this.nfcCard,
    required this.reason,
    this.cardNumber,
    this.balance,
    this.transactions = const [],
    this.message =
        'Kartu berhasil terdeteksi, tetapi protokol saldo kartu ini tidak tersedia atau memerlukan akses khusus.',
  });

  final String cardType;
  final CardBrand brand;
  final NfcCard nfcCard;
  final String reason;
  final String? cardNumber;
  final CardBalance? balance;
  final List<CardTransaction> transactions;
  final String message;
}

final class CardUnsupported extends CardReadResult {
  const CardUnsupported({
    required this.detectedTechnology,
    required this.nfcCard,
    required this.reason,
    this.message =
        'Kartu terdeteksi, tetapi saldo belum dapat dibaca oleh aplikasi ini.',
  });

  final String detectedTechnology;
  final NfcCard nfcCard;
  final String reason;
  final String message;
}

final class CardReadFailure extends CardReadResult {
  const CardReadFailure({
    required this.reason,
    this.nfcCard,
    this.message = 'Gagal membaca kartu NFC.',
  });

  final String reason;
  final NfcCard? nfcCard;
  final String message;
}

abstract class CardAdapter {
  String get id;
  CardBrand get brand;
  String get displayName;

  bool canHandle(NfcCard card);

  /// Confidence 0..1 for selection ranking. Prefer strongest evidence.
  double confidence(NfcCard card) => canHandle(card) ? 0.5 : 0.0;

  Future<CardReadResult> readCard(NfcCard card);
}
