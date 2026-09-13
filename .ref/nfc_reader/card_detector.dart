import 'package:nfc_card_reader/core/utils/hex_utils.dart';
import 'package:nfc_card_reader/features/cards/domain/card_adapter.dart';
import 'package:nfc_card_reader/features/scanner/domain/entities/nfc_card.dart';

class CardDetector {
  CardDetector(this.adapters);

  final List<CardAdapter> adapters;

  CardAdapter detect(NfcCard card) {
    CardAdapter? best;
    var bestScore = 0.0;

    for (final adapter in adapters) {
      if (!adapter.canHandle(card)) {
        continue;
      }
      final score = adapter.confidence(card);
      if (score > bestScore) {
        bestScore = score;
        best = adapter;
      }
    }

    return best ??
        adapters.firstWhere(
          (adapter) => adapter.id == 'unknown',
          orElse: () => adapters.last,
        );
  }

  List<CardAdapter> candidates(NfcCard card) {
    final matched =
        adapters.where((adapter) => adapter.canHandle(card)).toList()
          ..sort((a, b) => b.confidence(card).compareTo(a.confidence(card)));
    return matched;
  }
}

/// Shared conservative helpers — never claim a bank brand from UID alone.
class CardEvidence {
  const CardEvidence._();

  static bool looksLikeMifareClassic(NfcCard card) {
    final type = card.type.toLowerCase();
    final mifare = (card.mifareType ?? '').toLowerCase();
    return card.technology == NfcTechnology.mifareClassic ||
        type.contains('mifare_classic') ||
        type.contains('mifareclassic') ||
        mifare.contains('classic');
  }

  static bool looksLikeIso14443A(NfcCard card) {
    return card.isNfcA ||
        card.standard.toLowerCase().contains('iso 14443-a') ||
        card.standard.toLowerCase().contains('nfc-a');
  }

  static bool looksLikeFelica(NfcCard card) {
    return card.isNfcF ||
        card.standard.toLowerCase().contains('iso 18092') ||
        card.standard.toLowerCase().contains('felica') ||
        card.standard.toLowerCase().contains('nfc-f') ||
        (card.systemCode != null && card.systemCode!.isNotEmpty);
  }

  static String technologyLabel(NfcCard card) {
    if (card.standard.isNotEmpty && card.standard.toLowerCase() != 'unknown') {
      return card.standard;
    }
    return card.type;
  }

  static String debugDump(NfcCard card) {
    final lines = <String>[
      'ID: ${HexUtils.formatUid(card.id)}',
      'Type: ${card.type}',
      'Standard: ${card.standard}',
      'Technology: ${card.technology.name}',
      'Manufacturer: ${card.manufacturer ?? '-'}',
      'ATQA: ${card.atqa ?? '-'}',
      'SAK: ${card.sak ?? '-'}',
      'Historical Bytes: ${card.historicalBytes ?? '-'}',
      'System Code: ${card.systemCode ?? '-'}',
      'Protocol Info: ${card.protocolInfo ?? '-'}',
      'Application Data: ${card.applicationData ?? '-'}',
      'NDEF Available: ${card.ndefAvailable}',
      'NDEF Type: ${card.ndefType ?? '-'}',
      'NDEF Capacity: ${card.ndefCapacity ?? '-'}',
      'MIFARE Type: ${card.mifareType ?? '-'}',
      'Technologies: ${card.availableTechnologies.join(', ')}',
    ];
    card.rawMetadata.forEach((key, value) {
      lines.add('$key: $value');
    });
    return lines.join('\n');
  }
}
