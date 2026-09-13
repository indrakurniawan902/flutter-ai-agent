import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/domain/entities/chat/generative_card_data.dart';

/// Generative Micro-UI card for user action confirmation, authorizations,
/// and interactive CTA confirmations in chat stream.
class ActionConfirmationCard extends StatelessWidget {
  final ActionConfirmationData data;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final bool isLoading;

  const ActionConfirmationCard({
    super.key,
    required this.data,
    this.onConfirm,
    this.onCancel,
    this.isLoading = false,
  });

  String _formatJson(Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return '';
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(params);
    } catch (_) {
      return params.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasParameters = data.parameters != null && data.parameters!.isNotEmpty;
    final isDecided = data.isConfirmed || data.isDismissed;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: data.isConfirmed
              ? HermesColors.emerald.withValues(alpha: 0.6)
              : (data.isDismissed
                  ? HermesColors.danger.withValues(alpha: 0.5)
                  : HermesColors.border),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header / Tier badge
          _buildHeader(context),
          // Content body
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: const TextStyle(
                    color: HermesColors.inkPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  data.message,
                  style: const TextStyle(
                    color: HermesColors.inkSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (hasParameters) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      const Icon(
                        Icons.tune_rounded,
                        size: 14,
                        color: HermesColors.electricTeal,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Parameters',
                        style: HermesTypography.toolLabel(
                          color: HermesColors.electricTeal,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: HermesColors.codeBg,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: HermesColors.border),
                    ),
                    child: SelectableText(
                      _formatJson(data.parameters),
                      style: HermesTypography.jsonPayload(
                        color: HermesColors.inkSecondary,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Action Buttons or Decided Badge
          if (isDecided)
            _buildDecidedState()
          else
            _buildActionButtons(context),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final label = data.tierLabel ?? 'Action Confirmation';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: HermesColors.deepObsidian.withValues(alpha: 0.7),
        border: const Border(
          bottom: BorderSide(color: HermesColors.border, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.shield_outlined,
            size: 16,
            color: HermesColors.amber,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: HermesTypography.statusPill(
                color: HermesColors.amber,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDecidedState() {
    final isConfirmed = data.isConfirmed;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isConfirmed
            ? HermesColors.emerald.withValues(alpha: 0.1)
            : HermesColors.danger.withValues(alpha: 0.1),
        border: Border(
          top: BorderSide(
            color: isConfirmed
                ? HermesColors.emerald.withValues(alpha: 0.3)
                : HermesColors.danger.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isConfirmed ? Icons.check_circle : Icons.cancel_outlined,
            size: 16,
            color: isConfirmed ? HermesColors.emerald : HermesColors.danger,
          ),
          const SizedBox(width: 8),
          Text(
            isConfirmed ? 'Action Confirmed' : 'Action Declined',
            style: TextStyle(
              color: isConfirmed ? HermesColors.emerald : HermesColors.danger,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: HermesColors.border, width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                key: const Key('action_confirmation_secondary_btn'),
                icon: const Icon(Icons.close_rounded, size: 16),
                label: Text(data.secondaryActionLabel),
                style: OutlinedButton.styleFrom(
                  foregroundColor: HermesColors.inkSecondary,
                  side: const BorderSide(color: HermesColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: isLoading ? null : onCancel,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 44,
              child: ElevatedButton.icon(
                key: const Key('action_confirmation_primary_btn'),
                icon: isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: HermesColors.deepObsidian,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 16),
                label: Text(data.primaryActionLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: HermesColors.electricTeal,
                  foregroundColor: HermesColors.deepObsidian,
                  textStyle: const TextStyle(fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                ),
                onPressed: isLoading ? null : onConfirm,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
