import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/features/chat/domain/models/action_step.dart';

/// Interactive live action stepper card rendered in chat stream during
/// multi-step tool execution pipelines.
class LiveActionStepperCard extends StatefulWidget {
  final String title;
  final List<ActionStep> steps;
  final ValueChanged<ActionStep>? onStepTap;
  final bool initiallyExpanded;

  const LiveActionStepperCard({
    super.key,
    this.title = 'Action Execution Pipeline',
    required this.steps,
    this.onStepTap,
    this.initiallyExpanded = false,
  });

  @override
  State<LiveActionStepperCard> createState() => _LiveActionStepperCardState();
}

class _LiveActionStepperCardState extends State<LiveActionStepperCard> {
  final Set<String> _expandedStepIds = <String>{};

  @override
  void initState() {
    super.initState();
    if (widget.initiallyExpanded) {
      for (final step in widget.steps) {
        _expandedStepIds.add(step.id);
      }
    }
  }

  void _toggleExpansion(ActionStep step) {
    setState(() {
      if (_expandedStepIds.contains(step.id)) {
        _expandedStepIds.remove(step.id);
      } else {
        _expandedStepIds.add(step.id);
      }
    });
    widget.onStepTap?.call(step);
  }

  String _formatJson(dynamic data) {
    if (data == null) return '';
    if (data is String) return data;
    try {
      const encoder = JsonEncoder.withIndent('  ');
      return encoder.convert(data);
    } catch (_) {
      return data.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalSteps = widget.steps.length;
    final doneSteps = widget.steps.where((s) => s.status.isDone).length;
    final progress = totalSteps > 0 ? doneSteps / totalSteps : 0.0;

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
          _buildHeader(totalSteps, doneSteps, progress),
          if (totalSteps > 0)
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: totalSteps,
              separatorBuilder: (_, _) => Divider(
                height: 1,
                thickness: 0.8,
                color: HermesColors.border.withValues(alpha: 0.5),
                indent: 48,
              ),
              itemBuilder: (context, index) {
                final step = widget.steps[index];
                final isExpanded = _expandedStepIds.contains(step.id);
                return _buildStepTile(step, isExpanded);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(int total, int done, double progress) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: HermesColors.deepObsidian.withValues(alpha: 0.6),
        border: const Border(
          bottom: BorderSide(color: HermesColors.border, width: 0.8),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.alt_route_rounded,
                size: 18,
                color: HermesColors.electricTeal,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.title,
                  style: HermesTypography.toolLabel(
                    color: HermesColors.inkPrimary,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: HermesColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: done == total && total > 0
                        ? HermesColors.emerald
                        : HermesColors.border,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '$done/$total Completed',
                  style: HermesTypography.statusPill(
                    color: done == total && total > 0
                        ? HermesColors.emerald
                        : HermesColors.inkSecondary,
                    fontSize: 10,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: HermesColors.border,
              valueColor: const AlwaysStoppedAnimation<Color>(
                HermesColors.emerald,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepTile(ActionStep step, bool isExpanded) {
    return InkWell(
      onTap: () => _toggleExpansion(step),
      splashColor: HermesColors.electricTeal.withValues(alpha: 0.1),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _buildStatusIcon(step.status),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        step.title,
                        style: HermesTypography.monospace(
                          color: step.status.isDone
                              ? HermesColors.inkPrimary
                              : (step.status.isInProgress
                                  ? HermesColors.electricTeal
                                  : HermesColors.inkSecondary),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (step.description != null &&
                          step.description!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          step.description!,
                          style: const TextStyle(
                            color: HermesColors.inkMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 18,
                  color: HermesColors.inkMuted,
                ),
              ],
            ),
            if (isExpanded) _buildAccordionBody(step),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIcon(ActionStepStatus status) {
    switch (status) {
      case ActionStepStatus.done:
        return const Icon(
          Icons.check_circle,
          color: HermesColors.emerald,
          size: 20,
        );
      case ActionStepStatus.inProgress:
        return const SizedBox(
          width: 20,
          height: 20,
          child: Center(
            child: SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  HermesColors.electricTeal,
                ),
              ),
            ),
          ),
        );
      case ActionStepStatus.pending:
        return const Icon(
          Icons.radio_button_unchecked,
          color: HermesColors.inkMuted,
          size: 20,
        );
      case ActionStepStatus.error:
        return const Icon(
          Icons.error_outline,
          color: HermesColors.danger,
          size: 20,
        );
    }
  }

  Widget _buildAccordionBody(ActionStep step) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, left: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (step.parameters != null && step.parameters!.isNotEmpty) ...[
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
                _formatJson(step.parameters),
                style: HermesTypography.jsonPayload(
                  color: HermesColors.inkSecondary,
                  fontSize: 11,
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (step.output != null) ...[
            Row(
              children: [
                const Icon(
                  Icons.data_object_rounded,
                  size: 14,
                  color: HermesColors.emerald,
                ),
                const SizedBox(width: 6),
                Text(
                  'Output JSON',
                  style: HermesTypography.toolLabel(
                    color: HermesColors.emerald,
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
                _formatJson(step.output),
                style: HermesTypography.jsonPayload(
                  color: HermesColors.inkPrimary,
                  fontSize: 11,
                ),
              ),
            ),
          ],
          if (step.errorMessage != null && step.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: HermesColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: HermesColors.danger.withValues(alpha: 0.5)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 16,
                    color: HermesColors.danger,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      step.errorMessage!,
                      style: const TextStyle(
                        color: HermesColors.danger,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
