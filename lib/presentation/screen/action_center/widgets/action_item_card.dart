import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/domain/entities/action_center/action_item.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

/// Formats [time] as a compact relative label against [now].
String formatRelativeTime(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(time).abs();
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return '${(diff.inDays / 7).floor()}w ago';
}

Color _priorityColor(ActionItemPriority priority) {
  switch (priority) {
    case ActionItemPriority.low:
      return HermesColors.inkMuted;
    case ActionItemPriority.normal:
      return HermesColors.electricTeal;
    case ActionItemPriority.high:
      return HermesColors.amber;
  }
}

/// Expandable inbox card for a single [ActionItem].
///
/// Header shows a priority dot, the title and a relative timestamp; expanding
/// reveals the summary. A one-tap action button runs [onExecute] using the
/// payload `label` (fallback `Act`). Swipe-to-dismiss runs [onDismiss].
class ActionItemCard extends StatefulWidget {
  final ActionItem item;
  final VoidCallback onTap;
  final VoidCallback onDismiss;
  final VoidCallback onExecute;

  const ActionItemCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onDismiss,
    required this.onExecute,
  });

  @override
  State<ActionItemCard> createState() => _ActionItemCardState();
}

class _ActionItemCardState extends State<ActionItemCard> {
  bool _expanded = false;

  void _toggle() {
    setState(() => _expanded = !_expanded);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final dot = _priorityColor(item.priority);
    final label = item.actionPayload?['label']?.toString();
    final actionLabel = (label == null || label.isEmpty) ? 'Act' : label;

    return Dismissible(
      key: ValueKey('action_item_${item.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => widget.onDismiss(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: HermesColors.danger.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HermesColors.danger),
        ),
        child: const Icon(Icons.delete_outline, color: HermesColors.danger),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: HermesColors.cardSurface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HermesColors.border, width: 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: item.isRead
                    ? Colors.transparent
                    : HermesColors.accentTeal,
                width: item.isRead ? 0 : 3,
              ),
            ),
          ),
          child: InkWell(
            key: Key('action_card_${item.id}'),
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        key: Key('priority_dot_${item.id}'),
                        width: 8,
                        height: 8,
                        decoration:
                            BoxDecoration(color: dot, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: HermesColors.inkPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatRelativeTime(item.timestamp),
                        style: HermesTypography.monospace(
                          color: HermesColors.inkMuted,
                          fontSize: 11,
                        ),
                      ),
                      Icon(
                        _expanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 20,
                        color: HermesColors.inkSecondary,
                      ),
                    ],
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox(width: double.infinity),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.summary,
                            style: const TextStyle(
                              color: HermesColors.inkBody,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton(
                              key: Key('action_button_${item.id}'),
                              onPressed: widget.onExecute,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: HermesColors.accentTeal,
                                side: const BorderSide(
                                  color: HermesColors.accentTeal,
                                ),
                                minimumSize: const Size(0, 32),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: Text(
                                actionLabel,
                                style: HermesTypography.monospace(
                                  color: HermesColors.accentTeal,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    crossFadeState: _expanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 180),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
