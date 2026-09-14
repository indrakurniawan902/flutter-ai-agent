import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/services/skills/skills_registry_service.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/cubit/skills_state.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/skill_detail_sheet.dart';
import 'package:flutter_ai_agent/presentation/screen/skills/skill_import_dialog.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

/// Tab 2: Skills Hub
///
/// Features:
/// - Category filter pills (All, Productivity, Finance, Device Control, Automation).
/// - Dynamic search across title, description, and required tools.
/// - Hermes Nous terminal aesthetics with zero emojis.
/// - Active skill enable/disable toggle.
/// - Full skill detail modal with required device tools and sample prompts.
class SkillsHubScreen extends StatelessWidget {
  final SkillsCubit? cubit;

  const SkillsHubScreen({super.key, this.cubit});

  @override
  Widget build(BuildContext context) {
    if (cubit != null) {
      return BlocProvider<SkillsCubit>.value(
        value: cubit!,
        child: const _SkillsHubView(),
      );
    }

    try {
      BlocProvider.of<SkillsCubit>(context, listen: false);
      return const _SkillsHubView();
    } catch (_) {
      return BlocProvider<SkillsCubit>(
        create: (_) => sl.isRegistered<SkillsCubit>()
            ? sl<SkillsCubit>()
            : SkillsCubit(
                skillsRegistryService: sl.isRegistered<SkillsRegistryService>()
                    ? sl<SkillsRegistryService>()
                    : SkillsRegistryService(),
              ),
        child: const _SkillsHubView(),
      );
    }
  }
}

class _SkillsHubView extends StatefulWidget {
  const _SkillsHubView();

  @override
  State<_SkillsHubView> createState() => _SkillsHubViewState();
}

class _SkillsHubViewState extends State<_SkillsHubView> {
  final TextEditingController _searchController = TextEditingController();

  static const List<Map<String, String>> _categories = [
    {'id': 'all', 'label': 'All'},
    {'id': 'productivity', 'label': 'Productivity'},
    {'id': 'finance', 'label': 'Finance'},
    {'id': 'device', 'label': 'Device Control'},
    {'id': 'automations', 'label': 'Automation'},
    {'id': 'system', 'label': 'System'},
    {'id': 'vision', 'label': 'Vision'},
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    context.read<SkillsCubit>().search(_searchController.text);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool _isCategorySelected(String catId, String selectedCategory) {
    final cId = catId.toLowerCase();
    final sCat = selectedCategory.toLowerCase();
    if (cId == sCat) return true;
    if (cId == 'device' && (sCat == 'device' || sCat == 'device control')) {
      return true;
    }
    if (cId == 'automations' &&
        (sCat == 'automation' || sCat == 'automations')) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SkillsCubit, SkillsState>(
      builder: (context, state) {
        final activeCount = state is SkillsLoaded ? state.activeCount : 0;
        final selectedCategory =
            state is SkillsLoaded ? state.selectedCategory : 'all';
        final filtered =
            state is SkillsLoaded ? state.filteredSkills : const <Skill>[];

        return Scaffold(
          backgroundColor: HermesColors.deepObsidian,
          appBar: AppBar(
            title: const Text(
              'Skills Hub',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            actions: [
              IconButton(
                key: const Key('skills_import_button'),
                icon: const Icon(Icons.download_outlined),
                tooltip: 'Import skill from URL',
                color: HermesColors.inkSecondary,
                onPressed: () {
                  final cubit = context.read<SkillsCubit>();
                  showDialog<void>(
                    context: context,
                    builder: (_) => SkillImportDialog(cubit: cubit),
                  );
                },
              ),
              Container(
                margin: const EdgeInsets.only(right: 16),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: HermesColors.cardSurface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HermesColors.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 14,
                      color: HermesColors.emerald,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$activeCount Active',
                      style: HermesTypography.statusPill(
                        color: HermesColors.inkPrimary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  key: const Key('skills_search_field'),
                  controller: _searchController,
                  style: const TextStyle(
                    color: HermesColors.inkPrimary,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Search community & local skills...',
                    hintStyle: const TextStyle(
                      color: HermesColors.inkMuted,
                      fontSize: 13,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      size: 20,
                      color: HermesColors.inkSecondary,
                    ),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              size: 18,
                              color: HermesColors.inkMuted,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              context.read<SkillsCubit>().search('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: HermesColors.cardSurface,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: HermesColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: HermesColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide:
                          const BorderSide(color: HermesColors.electricTeal),
                    ),
                  ),
                ),
              ),
              SingleChildScrollView(
                key: const Key('skills_filter_pills'),
                scrollDirection: Axis.horizontal,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: _categories.map((cat) {
                    final isSelected =
                        _isCategorySelected(cat['id']!, selectedCategory);
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        key: Key('skills_filter_pill_${cat['id']}'),
                        label: Text(
                          cat['label']!,
                          style: HermesTypography.monospace(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: isSelected
                                ? HermesColors.electricTeal
                                : HermesColors.inkSecondary,
                          ),
                        ),
                        selected: isSelected,
                        onSelected: (_) {
                          context
                              .read<SkillsCubit>()
                              .selectCategory(cat['id']!);
                        },
                        backgroundColor: HermesColors.cardSurface,
                        selectedColor:
                            HermesColors.electricTeal.withValues(alpha: 0.15),
                        checkmarkColor: HermesColors.electricTeal,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                          side: BorderSide(
                            color: isSelected
                                ? HermesColors.electricTeal
                                : HermesColors.border,
                            width: isSelected ? 1.2 : 1.0,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        key: const Key('skills_empty_state'),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.extension_off_outlined,
                              size: 48,
                              color: HermesColors.inkMuted,
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'No matching skills found',
                              style: TextStyle(
                                color: HermesColors.inkSecondary,
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Try modifying search terms or category filter.',
                              style: HermesTypography.monospace(
                                fontSize: 12,
                                color: HermesColors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          return _SkillCard(
                            skill: item,
                            onToggle: (val) {
                              context
                                  .read<SkillsCubit>()
                                  .toggleSkill(item.id, val);
                            },
                            onTap: () {
                              SkillDetailSheet.show(
                                context,
                                skill: item,
                                onToggle: (val) {
                                  context
                                      .read<SkillsCubit>()
                                      .toggleSkill(item.id, val);
                                },
                              );
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkillCard extends StatelessWidget {
  final Skill skill;
  final ValueChanged<bool> onToggle;
  final VoidCallback onTap;

  const _SkillCard({
    required this.skill,
    required this.onToggle,
    required this.onTap,
  });

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
    return InkWell(
      key: Key('skill_card_${skill.id}'),
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: HermesColors.cardSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: skill.isEnabled
                ? HermesColors.border
                : HermesColors.border.withValues(alpha: 0.5),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _getCategoryIcon(skill.category),
                  size: 18,
                  color: skill.isEnabled
                      ? HermesColors.electricTeal
                      : HermesColors.inkMuted,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: HermesColors.deepObsidian,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: HermesColors.border),
                    ),
                    child: Text(
                      skill.name,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: HermesTypography.monospace(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: skill.isEnabled
                            ? HermesColors.electricTeal
                            : HermesColors.inkMuted,
                      ),
                    ),
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
                const Spacer(),
                Switch.adaptive(
                  key: Key('skill_toggle_${skill.id}'),
                  value: skill.isEnabled,
                  activeThumbColor: HermesColors.electricTeal,
                  activeTrackColor:
                      HermesColors.electricTeal.withValues(alpha: 0.3),
                  inactiveThumbColor: HermesColors.inkMuted,
                  inactiveTrackColor: HermesColors.deepObsidian,
                  onChanged: onToggle,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              skill.description,
              style: const TextStyle(
                fontSize: 13,
                color: HermesColors.inkBody,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                if (skill.tools.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: HermesColors.deepObsidian,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: HermesColors.hairline),
                    ),
                    child: Text(
                      '${skill.tools.length} TOOLS',
                      style: HermesTypography.monospace(
                        fontSize: 9,
                        color: HermesColors.inkMuted,
                      ),
                    ),
                  ),
                if (skill.isCommunity)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: HermesColors.electricTeal.withValues(alpha: 0.15),
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
    );
  }
}
