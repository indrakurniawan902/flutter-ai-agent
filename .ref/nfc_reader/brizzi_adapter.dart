import 'package:nfc_card_reader/features/cards/domain/card_adapter.dart';
import 'package:nfc_card_reader/features/scanner/domain/entities/nfc_card.dart';

/// BRIZZI balance requires proprietary issuer keys / terminal APIs.
/// This adapter only activates when reliable brand evidence is present.
class BrizziAdapter extends CardAdapter {
  @override
  String get id => 'brizzi';

  @override
  CardBrand get brand => CardBrand.brizzi;

  @override
  String get displayName => 'BRIZZI';

  @override
  bool canHandle(NfcCard card) {
    final confirmed = card.rawMetadata['confirmed_brand']?.toLowerCase();
    final aid = card.rawMetadata['application_id']?.toUpperCase() ?? '';
    return confirmed == 'brizzi' || aid.contains('BRIZZI');
  }

  @override
  double confidence(NfcCard card) {
    if (!canHandle(card)) {
      return 0;
    }
    return card.rawMetadata['confirmed_brand'] == 'brizzi' ? 0.95 : 0.7;
  }

  @override
  Future<CardReadResult> readCard(NfcCard card) async {
    return CardPartiallyRead(
      cardType: displayName,
      brand: brand,
      nfcCard: card,
      cardNumber: null,
      reason:
          'Protokol saldo BRIZZI memerlukan kunci/issuer API yang tidak tersedia secara publik. Aplikasi ini tidak melakukan autentikasi sektor MIFARE yang dilindungi.',
      message:
          'Kartu terdeteksi sebagai kandidat BRIZZI, tetapi saldo tidak dapat dibaca secara sah oleh aplikasi ini.',
    );
  }
}
