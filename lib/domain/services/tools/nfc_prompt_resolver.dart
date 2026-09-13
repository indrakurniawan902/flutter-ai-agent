import 'package:flutter_ai_agent/domain/entities/chat/nfc_tag_prompt_binding.dart';

/// Resolves an NFC card UID to a bound prompt string.
/// Pure Dart, no Flutter, no plugin deps.
class NfcPromptResolver {
  final List<NfcTagPromptBinding> bindings;

  const NfcPromptResolver({required this.bindings});

  String? resolve(String cardUid) {
    final normalized = cardUid.trim().toLowerCase();
    for (final binding in bindings) {
      if (binding.cardUid == normalized) {
        return binding.prompt;
      }
    }
    return null;
  }
}
