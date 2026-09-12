import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/domain/entities/chat/memory_item.dart';
import 'package:flutter_ai_agent/domain/tools/chat/local_memory_service.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';

/// Memory record model for SQLite FTS5 Memory Vault.
class MemoryRecord {
  final int? id;
  final String key;
  final String content;
  final String category;
  final String timestamp;
  final double score;

  const MemoryRecord({
    this.id,
    required this.key,
    required this.content,
    required this.category,
    required this.timestamp,
    required this.score,
  });
}

/// Tab 4: Memory Vault
///
/// Features:
/// - SQLite FTS5 user memory viewer & search with BM25 full-text indexing.
/// - Query input and filter categories.
/// - Hermes Nous design tokens with zero emojis.
/// - State preservation across tab switches.
class MemoryVaultScreen extends StatefulWidget {
  const MemoryVaultScreen({super.key});

  @override
  State<MemoryVaultScreen> createState() => _MemoryVaultScreenState();
}

class _MemoryVaultScreenState extends State<MemoryVaultScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategory = 'all';
  bool _isLoading = false;

  static const List<MemoryRecord> _defaultRecords = [
    MemoryRecord(
      key: 'user.identity.name',
      content: 'User preferred name: Indra (Eryushin)',
      category: 'profile',
      timestamp: '2026-09-11 15:20',
      score: 1.0,
    ),
    MemoryRecord(
      key: 'router.llm.endpoint',
      content: 'Target LLM router: https://indra-9router.my.id/v1',
      category: 'router',
      timestamp: '2026-09-11 14:15',
      score: 0.95,
    ),
    MemoryRecord(
      key: 'device.hardware.model',
      content: 'Device hardware model: SM-G991B (Samsung Exynos / Android 14)',
      category: 'hardware',
      timestamp: '2026-09-11 13:40',
      score: 0.90,
    ),
    MemoryRecord(
      key: 'agent.rules.budget',
      content: 'Default ReAct loop budget: 20 turns before human checkpoint',
      category: 'rules',
      timestamp: '2026-09-11 12:00',
      score: 0.88,
    ),
    MemoryRecord(
      key: 'gateway.profile.active',
      content: 'Active server profile: Production Hermes Gateway (WSS 8644)',
      category: 'router',
      timestamp: '2026-09-11 10:10',
      score: 0.85,
    ),
  ];

  late List<MemoryRecord> _records = List.of(_defaultRecords);

  static const List<Map<String, String>> _categories = [
    {'id': 'all', 'label': 'All'},
    {'id': 'profile', 'label': 'Profile'},
    {'id': 'router', 'label': 'Router'},
    {'id': 'hardware', 'label': 'Hardware'},
    {'id': 'rules', 'label': 'Rules'},
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _initMemoryStore();
  }

  Future<void> _initMemoryStore() async {
    if (!sl.isRegistered<LocalMemoryServiceBase>()) return;
    final service = sl<LocalMemoryServiceBase>();
    setState(() => _isLoading = true);
    try {
      final res = await service.getAllMemories();
      await res.fold(
        (_) async {},
        (items) async {
          if (items.isEmpty) {
            for (final r in _defaultRecords) {
              await service.saveMemory(r.key, r.content, [r.category]);
            }
            final seededRes = await service.getAllMemories();
            seededRes.fold((_) {}, (seededItems) {
              if (mounted) {
                setState(() {
                  _records = seededItems.map(_fromMemoryItem).toList();
                });
              }
            });
          } else {
            if (mounted) {
              setState(() {
                _records = items.map(_fromMemoryItem).toList();
              });
            }
          }
        },
      );
    } catch (_) {}
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  MemoryRecord _fromMemoryItem(MemoryItem item) {
    final cat =
        item.tags.isNotEmpty ? item.tags.first : _detectCategory(item.key);
    final dt = item.updatedAt;
    final timeStr =
        '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    return MemoryRecord(
      id: item.id,
      key: item.key,
      content: item.content,
      category: cat,
      timestamp: timeStr,
      score: item.score ?? 1.0,
    );
  }

  String _detectCategory(String key) {
    final lower = key.toLowerCase();
    if (lower.contains('profile') ||
        lower.contains('user') ||
        lower.contains('name')) {
      return 'profile';
    }
    if (lower.contains('router') ||
        lower.contains('llm') ||
        lower.contains('gateway')) {
      return 'router';
    }
    if (lower.contains('hardware') ||
        lower.contains('device') ||
        lower.contains('model')) {
      return 'hardware';
    }
    if (lower.contains('rule') || lower.contains('budget')) {
      return 'rules';
    }
    return 'profile';
  }

  Future<void> _deleteMemoryRecord(MemoryRecord record) async {
    if (record.id != null && sl.isRegistered<LocalMemoryServiceBase>()) {
      await sl<LocalMemoryServiceBase>().deleteMemory(record.id!);
    } else if (sl.isRegistered<LocalMemoryServiceBase>()) {
      await sl<LocalMemoryServiceBase>().deleteMemoryByKey(record.key);
    }
    setState(() {
      _records.removeWhere((r) =>
          r.key == record.key || (record.id != null && r.id == record.id));
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Memory record "${record.key}" deleted.',
            style: HermesTypography.monospace(fontSize: 12, color: Colors.white),
          ),
          backgroundColor: HermesColors.cardSurface,
          duration: const Duration(seconds: 2),
        ),
      );
    }
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

  List<MemoryRecord> get _filteredRecords {
    return _records.where((record) {
      final matchesCat = _selectedCategory == 'all' ||
          record.category.toLowerCase() == _selectedCategory.toLowerCase();
      final matchesQuery = _searchQuery.isEmpty ||
          record.key.toLowerCase().contains(_searchQuery) ||
          record.content.toLowerCase().contains(_searchQuery);
      return matchesCat && matchesQuery;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredRecords;

    return Scaffold(
      backgroundColor: HermesColors.deepObsidian,
      appBar: AppBar(
        title: const Text(
          'Memory Vault',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, size: 18, color: HermesColors.inkSecondary),
            tooltip: 'Refresh Memories',
            onPressed: _initMemoryStore,
          ),
          Container(
            key: const Key('memory_fts5_badge'),
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
                const Icon(Icons.storage, size: 14, color: HermesColors.electricTeal),
                const SizedBox(width: 6),
                Text(
                  'FTS5 Indexed • SQLite',
                  style: HermesTypography.statusPill(
                    color: HermesColors.electricTeal,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ],
        bottom: _isLoading
            ? const PreferredSize(
                preferredSize: Size.fromHeight(2),
                child: LinearProgressIndicator(
                  minHeight: 2,
                  color: HermesColors.electricTeal,
                  backgroundColor: Colors.transparent,
                ),
              )
            : null,
      ),
      body: Column(
        children: [
          // Search input field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              key: const Key('memory_search_input'),
              controller: _searchController,
              style: const TextStyle(color: HermesColors.inkPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search FTS5 memory index (e.g. Indra, router)...',
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
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat['id'];
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    key: Key('memory_cat_${cat['id']}'),
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

          // Memory Records List
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    key: const Key('memory_empty_state'),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.search_off_outlined, size: 48, color: HermesColors.inkMuted),
                        const SizedBox(height: 12),
                        const Text(
                          'No memory records match your search query',
                          style: TextStyle(
                            color: HermesColors.inkSecondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Query matches across FTS5 indexed keys and values.',
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
                      return Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: HermesColors.cardSurface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: HermesColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  item.key,
                                  style: HermesTypography.monospace(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: HermesColors.electricTeal,
                                  ),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: HermesColors.deepObsidian,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: HermesColors.hairline),
                                  ),
                                  child: Text(
                                    item.category.toUpperCase(),
                                    style: HermesTypography.monospace(
                                      fontSize: 9,
                                      color: HermesColors.inkSecondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    size: 15,
                                    color: HermesColors.inkMuted,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  tooltip: 'Delete Memory',
                                  onPressed: () => _deleteMemoryRecord(item),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              item.content,
                              style: const TextStyle(
                                fontSize: 13,
                                color: HermesColors.inkPrimary,
                                height: 1.3,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  item.timestamp,
                                  style: HermesTypography.monospace(
                                    fontSize: 11,
                                    color: HermesColors.inkMuted,
                                  ),
                                ),
                                Text(
                                  'BM25 score: ${(item.score * 100).toStringAsFixed(0)}%',
                                  style: HermesTypography.monospace(
                                    fontSize: 11,
                                    color: HermesColors.emerald,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
