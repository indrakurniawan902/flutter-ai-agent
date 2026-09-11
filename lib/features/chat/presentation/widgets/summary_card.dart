import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/features/chat/domain/models/generative_card_data.dart';

/// Generative Micro-UI card providing structured task/action summaries
/// with 1-tap clipboard copy and share actions.
class SummaryCard extends StatefulWidget {
  final SummaryCardData data;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;

  const SummaryCard({
    super.key,
    required this.data,
    this.onCopy,
    this.onShare,
  });

  @override
  State<SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends State<SummaryCard> {
  bool _copied = false;
  Timer? _copyTimer;

  @override
  void dispose() {
    _copyTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.data.summaryText));
    widget.onCopy?.call();

    if (mounted) {
      setState(() {
        _copied = true;
      });
      _copyTimer?.cancel();
      _copyTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _copied = false;
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasItems = widget.data.items.isNotEmpty;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HermesColors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.data.title,
                  style: const TextStyle(
                    color: HermesColors.inkPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.data.summaryText,
                  style: const TextStyle(
                    color: HermesColors.inkSecondary,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
                if (hasItems) ...[
                  const SizedBox(height: 12),
                  _buildMetricGrid(),
                ],
              ],
            ),
          ),
          _buildActionBar(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
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
            Icons.summarize_outlined,
            size: 16,
            color: HermesColors.electricTeal,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Summary Report',
              style: HermesTypography.statusPill(
                color: HermesColors.electricTeal,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricGrid() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: HermesColors.codeBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: HermesColors.border),
      ),
      child: Column(
        children: widget.data.items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item.label,
                  style: const TextStyle(
                    color: HermesColors.inkMuted,
                    fontSize: 12,
                  ),
                ),
                Text(
                  item.value,
                  style: HermesTypography.monospace(
                    color: HermesColors.inkPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: HermesColors.border, width: 0.8),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          SizedBox(
            height: 38,
            child: TextButton.icon(
              key: const Key('summary_card_copy_btn'),
              icon: Icon(
                _copied ? Icons.check_rounded : Icons.content_copy_rounded,
                size: 16,
                color: _copied ? HermesColors.emerald : HermesColors.inkSecondary,
              ),
              label: Text(
                _copied ? 'Copied' : 'Copy',
                style: TextStyle(
                  color: _copied ? HermesColors.emerald : HermesColors.inkSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: _handleCopy,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 38,
            child: TextButton.icon(
              key: const Key('summary_card_share_btn'),
              icon: const Icon(
                Icons.share_rounded,
                size: 16,
                color: HermesColors.electricTeal,
              ),
              label: const Text(
                'Share',
                style: TextStyle(
                  color: HermesColors.electricTeal,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              style: TextButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: widget.onShare,
            ),
          ),
        ],
      ),
    );
  }
}
