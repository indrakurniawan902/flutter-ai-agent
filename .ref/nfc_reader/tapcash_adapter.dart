import 'package:nfc_card_reader/features/cards/domain/card_adapter.dart';
import 'package:nfc_card_reader/features/scanner/domain/entities/nfc_card.dart';

class TapCashAdapter extends CardAdapter {
  @override
  String get id => 'tapcash';

  @override
  CardBrand get brand => CardBrand.tapCash;

  @override
  String get displayName => 'BNI TapCash';

  @override
  bool canHandle(NfcCard card) {
    final confirmed = card.rawMetadata['confirmed_brand']?.toLowerCase();
    final aid = card.rawMetadata['application_id']?.toUpperCase() ?? '';
    return confirmed == 'tapcash' || aid.contains('TAPCASH');
  }

  @override
  double confidence(NfcCard card) => canHandle(card) ? 0.9 : 0;

  @override
  Future<CardReadResult> readCard(NfcCard card) async {
    return CardPartiallyRead(
      cardType: displayName,
      brand: brand,
      nfcCard: card,
      reason:
          'TapCash memerlukan autentikasi issuer. Tanpa API/kunci resmi, hanya metadata NFC yang dapat ditampilkan.',
    );
  }
}
