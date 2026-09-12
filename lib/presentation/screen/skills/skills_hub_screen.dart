import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

/// Skill representation for the Skills Hub.
class SkillItem {
  final String name;
  final String description;
  final String category;
  final String tier;
  final String version;
  final bool isCommunity;
  bool isEnabled;

  SkillItem({
    required this.name,
    required this.description,
    required this.category,
    required this.tier,
    required this.version,
    this.isCommunity = false,
    this.isEnabled = true,
  });
}

/// Tab 2: Skills Hub
///
/// Features:
/// - Community & local skills.
/// - Category filter pills (All, Device, Automations, System, Vision).
/// - Dynamic search and state preservation.
/// - Hermes Nous terminal aesthetics with zero emojis.
class SkillsHubScreen extends StatefulWidget {
  const SkillsHubScreen({super.key});

  @override
  State<SkillsHubScreen> createState() => _SkillsHubScreenState();
}

class _SkillsHubScreenState extends State<SkillsHubScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = 'all';
  String _searchQuery = '';

  final List<SkillItem> _skills = [
    SkillItem(
      name: 'camera_vision',
      description: 'Camera image perception and visual reasoning via vision models',
      category: 'vision',
      tier: 'Tier 2 Perm',
      version: 'v1.2.0',
    ),
    SkillItem(
      name: 'location_context',
      description: 'Geofence tracking, coordinates and reverse geocoding telemetry',
      category: 'device',
      tier: 'Tier 2 Perm',
      version: 'v1.0.4',
    ),
    SkillItem(
      name: 'device_telemetry',
      description: 'Hardware battery percentage, charging state and network connectivity',
      category: 'system',
      tier: 'Tier 1 Auto',
      version: 'v2.1.0',
    ),
    SkillItem(
      name: 'clipboard_manager',
      description: 'Native secure clipboard text reading and writing bridge',
      category: 'system',
      tier: 'Tier 1 Auto',
      version: 'v1.1.0',
    ),
    SkillItem(
      name: 'calendar_scheduler',
      description: 'Calendar event retrieval, conflict detection and event creation',
      category: 'device',
      tier: 'Tier 3 HITL',
      version: 'v1.0.1',
    ),
    SkillItem(
      name: 'notification_pusher',
      description: 'Local reminder notification scheduling and background delivery',
      category: 'automations',
      tier: 'Tier 2 Perm',
      version: 'v1.3.0',
    ),
    SkillItem(
      name: 'ambient_observer',
      description: 'Background sensor polling and automated ambient event routing',
      category: 'automations',
      tier: 'Tier 1 Auto',
      version: 'v1.0.0',
      isCommunity: true,
    ),
    SkillItem(
      name: 'sqlite_fts5',
      description: 'Full-text indexed user memory storage with BM25 ranking',
      category: 'system',
      tier: 'Tier 1 Auto',
      version: 'v2.0.0',
    ),
  ];

  static const List<Map<String, String>> _categories = [
    {'id': 'all', 'label': 'All'},
    {'id': 'device', 'label': 'Device'},
    {'id': 'automations', 'label': 'Automations'},
    {'id': 'system', 'label': 'System'},
    {'id': 'vision', 'label': 'Vision'},
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text.trim().toLowerCase();
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  List<SkillItem> get _filteredSkills {
    return _skills.where((skill) {
      final matchesCategory = _selectedCategory == 'all' ||
          skill.category.toLowerCase() == _selectedCategory.toLowerCase();
      final matchesQuery = _searchQuery.isEmpty ||
          skill.name.toLowerCase().contains(_searchQuery) ||
          skill.description.toLowerCase().contains(_searchQuery);
      return matchesCategory && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredSkills;

    return Scaffold(
      backgroundColor: HermesColors.deepObsidian,
      appBar: AppBar(
        title: const Text(
          'Skills Hub',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: HermesColors.cardSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HermesColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, size: 14, color: HermesColors.emerald),
                const SizedBox(width: 6),
                Text(
                  '${_skills.where((s) => s.isEnabled).length} Active',
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
          // Search input
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              key: const Key('skills_search_field'),
              controller: _searchController,
              style: const TextStyle(color: HermesColors.inkPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search community & local skills...',
                hintStyle: const TextStyle(color: HermesColors.inkMuted, fontSize: 13),
                prefixIcon: const Icon(Icons.search, size: 20, color: HermesColors.inkSecondary),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: HermesColors.inkMuted),
                        onPressed: () => _searchController.clear(),
                      )
                    : null,
                filled: true,
                fillColor: HermesColors.cardSurface,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                  borderSide: const BorderSide(color: HermesColors.electricTeal),
                ),
              ),
            ),
          ),

          // Category filter pills
          SingleChildScrollView(
            key: const Key('skills_filter_pills'),
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat['id'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: Key('skills_filter_pill_${cat['id']}'),
                    label: Text(
                      cat['label']!,
                      style: HermesTypography.monospace(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? HermesColors.electricTeal : HermesColors.inkSecondary,
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() {
                        _selectedCategory = cat['id']!;
                      });
                    },
                    backgroundColor: HermesColors.cardSurface,
                    selectedColor: HermesColors.electricTeal.withValues(alpha: 0.15),
                    checkmarkColor: HermesColors.electricTeal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? HermesColors.electricTeal : HermesColors.border,
                        width: isSelected ? 1.2 : 1.0,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Skill Cards List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    key: const Key('skills_empty_state'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.extension_off_outlined, size: 48, color: HermesColors.inkMuted),
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
                    separatorBuilder: (context, index) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      return _SkillCard(
                        skill: item,
                        onToggle: (val) {
                          setState(() {
                            item.isEnabled = val;
                          });
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SkillCard extends StatelessWidget {
  final SkillItem skill;
  final ValueChanged<bool> onToggle;

  const _SkillCard({
    required this.skill,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: skill.isEnabled ? HermesColors.border : HermesColors.border.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: HermesColors.deepObsidian,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: HermesColors.border),
                ),
                child: Text(
                  skill.name,
                  style: HermesTypography.monospace(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: skill.isEnabled ? HermesColors.electricTeal : HermesColors.inkMuted,
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
                value: skill.isEnabled,
                activeThumbColor: HermesColors.electricTeal,
                activeTrackColor: HermesColors.electricTeal.withValues(alpha: 0.3),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: HermesColors.deepObsidian,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: HermesColors.hairline),
                ),
                child: Text(
                  skill.tier,
                  style: HermesTypography.tierBadge(
                    color: skill.tier.contains('HITL')
                        ? HermesColors.amber
                        : (skill.tier.contains('Auto') ? HermesColors.emerald : HermesColors.electricTeal),
                    fontSize: 10,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
              if (skill.isCommunity) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            ],
          ),
        ],
      ),
    );
  }
}
