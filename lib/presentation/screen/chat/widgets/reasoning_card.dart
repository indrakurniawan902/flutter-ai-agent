import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/theme/hermes_theme.dart';

/// Collapsible accordion card displaying the agent reasoning trace.
class ReasoningCard extends StatefulWidget {
  final String thoughtProcess;
  final bool initiallyExpanded;

  const ReasoningCard({
    super.key,
    required this.thoughtProcess,
    this.initiallyExpanded = false,
  });

  @override
  State<ReasoningCard> createState() => _ReasoningCardState();
}

class _ReasoningCardState extends State<ReasoningCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HermesColors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            button: true,
            expanded: _expanded,
            label: 'Thought Process',
            child: InkWell(
              key: const Key('reasoning_card_header'),
              onTap: _toggle,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.psychology_outlined,
                      size: 16,
                      color: HermesColors.electricTeal,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Thought Process',
                        style: TextStyle(
                          color: HermesColors.inkPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      size: 20,
                      color: HermesColors.inkSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _expanded
                ? Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: const BoxDecoration(
                      color: HermesColors.codeBg,
                      border: Border(
                        top: BorderSide(
                          color: HermesColors.border,
                          width: 0.8,
                        ),
                      ),
                    ),
                    child: Text(
                      widget.thoughtProcess,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.4,
                        color: HermesColors.inkSecondary,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}
