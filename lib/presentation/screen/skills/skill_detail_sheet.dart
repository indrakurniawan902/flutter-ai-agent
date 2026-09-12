import 'package:flutter/material.dart';

import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

/// Modal bottom sheet displaying detailed skill metadata, required device tools,
/// instructions, and sample user prompts.
class SkillDetailSheet extends StatelessWidget {
  final Skill skill;
  final ValueChanged<bool>? onToggle;

  const SkillDetailSheet({
    super.key,
    required this.skill,
    this.onToggle,
  });

  static Future<void> show(
    BuildContext context, {
    required Skill skill,
    ValueChanged<bool>? onToggle,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SkillDetailSheet(
        skill: skill,
        onToggle: onToggle,
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'productivity':
        return Icons.task_alt;
      case 'finance':
        return Icons.account_balance_wallet_outlined;
      case 'device control':
      case 'device':
        return Icons.perm_device_information;
      case 'automation':
      case 'automations':
        return Icons.auto_mode;
      case 'vision':
        return Icons.remove_red_eye_outlined;
      case 'system':
        return Icons.memory;
      default:
        return Icons.extension_outlined;
    }
  }

  Color _getTierColor(String tier) {
    if (tier.contains('HITL')) return HermesColors.amber;
    if (tier.contains('Auto')) return HermesColors.emerald;
    return HermesColors.electricTeal;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('skill_detail_sheet'),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: const BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(color: HermesColors.border, width: 1.2),
          left: BorderSide(color: HermesColors.border, width: 1.0),
          right: BorderSide(color: HermesColors.border, width: 1.0),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: HermesColors.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: HermesColors.deepObsidian,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: HermesColors.border),
                  ),
                  child: Icon(
                    _getCategoryIcon(skill.category),
                    size: 22,
                    color: HermesColors.electricTeal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              skill.name,
                              style: HermesTypography.monospace(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: HermesColors.inkPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            skill.version,
                            style: HermesTypography.monospace(
                              fontSize: 11,
                              color: HermesColors.inkMuted,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: HermesColors.deepObsidian,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: HermesColors.hairline),
                            ),
                            child: Text(
                              skill.tier,
                              style: HermesTypography.tierBadge(
                                color: _getTierColor(skill.tier),
                                fontSize: 10,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: HermesColors.deepObsidian,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              skill.category.toUpperCase(),
                              style: HermesTypography.monospace(
                                fontSize: 10,
                                color: HermesColors.inkSecondary,
                              ),
                            ),
                          ),
                          if (skill.isCommunity)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: HermesColors.electricTeal
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'COMMUNITY',
                                style: HermesTypography.monospace(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: HermesColors.electricTeal,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (onToggle != null) ...[
                  Switch.adaptive(
                    key: const Key('skill_detail_toggle'),
                    value: skill.isEnabled,
                    activeThumbColor: HermesColors.electricTeal,
                    activeTrackColor:
                        HermesColors.electricTeal.withValues(alpha: 0.3),
                    inactiveThumbColor: HermesColors.inkMuted,
                    inactiveTrackColor: HermesColors.deepObsidian,
                    onChanged: onToggle,
                  ),
                  const SizedBox(width: 4),
                ],
                IconButton(
                  key: const Key('skill_detail_close_button'),
                  icon: const Icon(Icons.close,
                      color: HermesColors.inkMuted, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(color: HermesColors.border, height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Description',
                    style: TextStyle(
                      color: HermesColors.inkMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    skill.description,
                    style: const TextStyle(
                      color: HermesColors.inkPrimary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Icon(Icons.build_outlined,
                          size: 16, color: HermesColors.electricTeal),
                      const SizedBox(width: 6),
                      const Text(
                        'Tool Requirements',
                        style: TextStyle(
                          color: HermesColors.inkPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (skill.tools.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: HermesColors.deepObsidian,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: HermesColors.border),
                      ),
                      child: Text(
                        'No device tools required (autonomous reasoning only)',
                        style: HermesTypography.monospace(
                          fontSize: 12,
                          color: HermesColors.inkMuted,
                        ),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: skill.tools.map((tool) {
                        return Container(
                          key: Key('modal_tool_$tool'),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: HermesColors.deepObsidian,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: HermesColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.terminal,
                                size: 13,
                                color: HermesColors.electricTeal,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                tool,
                                style: HermesTypography.monospace(
                                  fontSize: 12,
                                  color: HermesColors.inkPrimary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Icon(Icons.chat_bubble_outline,
                          size: 16, color: HermesColors.electricTeal),
                      const SizedBox(width: 6),
                      const Text(
                        'Sample Prompts',
                        style: TextStyle(
                          color: HermesColors.inkPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (skill.prompts.isEmpty)
                    Text(
                      'No sample prompts provided.',
                      style: HermesTypography.monospace(
                        fontSize: 12,
                        color: HermesColors.inkMuted,
                      ),
                    )
                  else
                    Column(
                      children: skill.prompts.asMap().entries.map((entry) {
                        final index = entry.key;
                        final prompt = entry.value;
                        return Container(
                          key: Key('modal_sample_prompt_$index'),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: HermesColors.deepObsidian,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: HermesColors.border),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.arrow_right,
                                size: 18,
                                color: HermesColors.electricTeal,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  prompt,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: HermesColors.inkPrimary,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  if (skill.instructions.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.description_outlined,
                            size: 16, color: HermesColors.electricTeal),
                        const SizedBox(width: 6),
                        const Text(
                          'Instructions & Policy',
                          style: TextStyle(
                            color: HermesColors.inkPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: HermesColors.deepObsidian,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: HermesColors.border),
                      ),
                      child: Text(
                        skill.instructions.trim(),
                        style: HermesTypography.monospace(
                          fontSize: 12,
                          color: HermesColors.inkSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
