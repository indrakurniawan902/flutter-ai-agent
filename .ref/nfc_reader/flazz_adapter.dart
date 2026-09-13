import 'package:nfc_card_reader/features/cards/domain/card_adapter.dart';
import 'package:nfc_card_reader/features/scanner/domain/entities/nfc_card.dart';

class FlazzAdapter extends CardAdapter {
  @override
  String get id => 'flazz';

  @override
  CardBrand get brand => CardBrand.flazz;

  @override
  String get displayName => 'BCA Flazz';

  @override
  bool canHandle(NfcCard card) {
    final confirmed = card.rawMetadata['confirmed_brand']?.toLowerCase();
    final aid = card.rawMetadata['application_id']?.toUpperCase() ?? '';
    return confirmed == 'flazz' || aid.contains('FLAZZ');
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
          'Saldo Flazz dilindungi protokol proprietary. Aplikasi ini tidak mengekstrak kunci atau mem-bypass kontrol akses kartu.',
    );
  }
}
