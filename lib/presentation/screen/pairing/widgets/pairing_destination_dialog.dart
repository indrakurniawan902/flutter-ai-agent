import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/domain/entities/pairing/pairing_payload.dart';
import 'package:flutter_ai_agent/domain/services/gateway/pairing_destination.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

/// Confirms the gateway origin a pairing payload will actually contact.
///
/// The payload is attacker-controlled, so the user must see the RESOLVED
/// socket origin - never the raw payload string - and take an affirmative
/// action before any profile is written or any socket is opened.
class PairingDestinationDialog extends StatelessWidget {
  final PairingPayload payload;

  /// Origin of the currently active gateway, when one is configured.
  ///
  /// Used only to render the replacement notice.
  final String? currentGatewayOrigin;

  const PairingDestinationDialog({
    super.key,
    required this.payload,
    this.currentGatewayOrigin,
  });

  @override
  Widget build(BuildContext context) {
    final destination = resolvePairingDestination(payload.gatewayUrl);
    // Never fall back to the raw payload string: that would silently downgrade
    // this control from "the resolved origin" to attacker-controlled text.
    // An unresolvable destination is shown as an explicit failure instead.
    final resolvedOrigin = destination?.displayOrigin ??
        'Destination could not be resolved';
    final isPlaintext = destination?.isPlaintext ?? false;
    // Producers hand over the raw stored profile URL, so normalize it through
    // the same resolver before comparing: re-pairing to the gateway already in
    // use must not read as a replacement.
    final currentResolvedOrigin = currentGatewayOrigin == null
        ? null
        : (resolvePairingDestination(currentGatewayOrigin!)?.displayOrigin ??
            currentGatewayOrigin);
    final replacesExisting = currentResolvedOrigin != null &&
        currentResolvedOrigin.isNotEmpty &&
        currentResolvedOrigin != resolvedOrigin;

    return AlertDialog(
      key: const Key('pairing_destination_dialog'),
      backgroundColor: HermesColors.deepObsidian,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: HermesColors.border),
      ),
      title: const Text(
        'Confirm Pairing Destination',
        style: TextStyle(
          color: HermesColors.inkPrimary,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The app will connect and authenticate to this gateway origin '
              'and share the device tool channel with it.',
              style: TextStyle(
                color: HermesColors.inkSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: HermesColors.cardSurface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: HermesColors.border),
              ),
              child: Text(
                resolvedOrigin,
                key: const Key('pairing_destination_origin'),
                style: const TextStyle(
                  color: HermesColors.inkPrimary,
                  fontFamily: 'monospace',
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              payload.profileName,
              key: const Key('pairing_destination_profile_name'),
              style: const TextStyle(
                color: HermesColors.inkSecondary,
                fontSize: 13,
              ),
            ),
            if (isPlaintext) ...[
              const SizedBox(height: 12),
              Row(
                key: const Key('pairing_destination_plaintext_warning'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Icon(
                    Icons.lock_open_rounded,
                    size: 16,
                    color: HermesColors.amber,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This connection is unencrypted. Only pair with a '
                      'gateway on your local network.',
                      style: TextStyle(
                        color: HermesColors.amber,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            if (replacesExisting) ...[
              const SizedBox(height: 12),
              Text(
                'This will replace your current gateway. '
                'Previous: $currentResolvedOrigin  New: $resolvedOrigin',
                key: const Key('pairing_destination_replacement_notice'),
                style: const TextStyle(
                  color: HermesColors.rose,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('pairing_destination_cancel_button'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(
            'Cancel',
            style: TextStyle(color: HermesColors.rose),
          ),
        ),
        ElevatedButton(
          key: const Key('pairing_destination_confirm_button'),
          style: ElevatedButton.styleFrom(
            backgroundColor: HermesColors.accentTeal,
            foregroundColor: HermesColors.inkPrimary,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

/// Shows the destination confirmation and reports whether the user consented.
///
/// Dismissing the dialog (barrier tap, back button) yields `false`, so an
/// accidental dismissal can never be read as consent.
Future<bool> showPairingDestinationConfirmation(
  BuildContext context, {
  required PairingPayload payload,
  String? currentGatewayOrigin,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => PairingDestinationDialog(
      payload: payload,
      currentGatewayOrigin: currentGatewayOrigin,
    ),
  );
  return confirmed ?? false;
}
