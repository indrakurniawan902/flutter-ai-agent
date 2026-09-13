import 'package:nfc_card_reader/features/cards/domain/card_adapter.dart';
import 'package:nfc_card_reader/features/scanner/domain/entities/nfc_card.dart';

class MandiriEmoneyAdapter extends CardAdapter {
  @override
  String get id => 'mandiri_emoney';

  @override
  CardBrand get brand => CardBrand.mandiriEmoney;

  @override
  String get displayName => 'Mandiri e-Money';

  @override
  bool canHandle(NfcCard card) {
    final confirmed = card.rawMetadata['confirmed_brand']?.toLowerCase();
    final aid = card.rawMetadata['application_id']?.toUpperCase() ?? '';
    return confirmed == 'mandiri_emoney' ||
        confirmed == 'mandiri' ||
        aid.contains('MANDIRI');
  }

  @override
  double confidence(NfcCard card) {
    if (!canHandle(card)) {
      return 0;
    }
    return 0.9;
  }

  @override
  Future<CardReadResult> readCard(NfcCard card) async {
    return CardPartiallyRead(
      cardType: displayName,
      brand: brand,
      nfcCard: card,
      reason:
          'Pembacaan saldo Mandiri e-Money membutuhkan protokol issuer yang tidak diekspos untuk aplikasi pihak ketiga tanpa akses resmi.',
      message:
          'Informasi saldo tidak dapat dibaca. Deteksi merek hanya dilakukan bila ada bukti protokol yang andal.',
    );
  }
}
