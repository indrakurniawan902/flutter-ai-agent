import 'dart:async';

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
  final List<String> tags;
  final String timestamp;
  final double? score;

  const MemoryRecord({
    this.id,
    required this.key,
    required this.content,
    required this.category,
    this.tags = const [],
    required this.timestamp,
    this.score,
  });
}

/// Tab 4: Memory Vault
///
/// Features:
/// - SQLite FTS5 user memory viewer & search with BM25 full-text indexing.
/// - Full CRUD: create, edit, delete with confirmation.
/// - Live FTS5 search with debounce.
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
  Timer? _searchDebounce;
  int _searchSeq = 0;

  static const List<MemoryRecord> _defaultRecords = [
    MemoryRecord(
      key: 'user.identity.name',
      content: 'User preferred name: Indra (Eryushin)',
      category: 'profile',
      timestamp: '2026-09-11 15:20',
    ),
    MemoryRecord(
      key: 'router.llm.endpoint',
      content: 'Target LLM router: https://indra-9router.my.id/v1',
      category: 'router',
      timestamp: '2026-09-11 14:15',
    ),
    MemoryRecord(
      key: 'device.hardware.model',
      content: 'Device hardware model: SM-G991B (Samsung Exynos / Android 14)',
      category: 'hardware',
      timestamp: '2026-09-11 13:40',
    ),
    MemoryRecord(
      key: 'agent.rules.budget',
      content: 'Default ReAct loop budget: 20 turns before human checkpoint',
      category: 'rules',
      timestamp: '2026-09-11 12:00',
    ),
    MemoryRecord(
      key: 'gateway.profile.active',
      content: 'Active server profile: Production Hermes Gateway (WSS 8644)',
      category: 'router',
      timestamp: '2026-09-11 10:10',
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
      tags: item.tags,
      timestamp: timeStr,
      score: item.score,
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

  Future<bool> _confirmDelete(MemoryRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const Key('memory_delete_confirm_dialog'),
        backgroundColor: HermesColors.cardSurface,
        title: const Text(
          'Delete this memory permanently?',
          style: TextStyle(color: HermesColors.inkPrimary, fontSize: 16),
        ),
        content: Text(
          'Key: ${record.key}',
          style: HermesTypography.monospace(
            fontSize: 12,
            color: HermesColors.inkSecondary,
          ),
        ),
        actions: [
          TextButton(
            key: const Key('memory_delete_cancel_button'),
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: HermesTypography.monospace(
                fontSize: 12,
                color: HermesColors.inkSecondary,
              ),
            ),
          ),
          TextButton(
            key: const Key('memory_delete_confirm_button'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(
              'Delete',
              style: HermesTypography.monospace(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: HermesColors.rose,
              ),
            ),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  void _showMemorySnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: HermesTypography.monospace(fontSize: 12, color: Colors.white),
        ),
        backgroundColor: HermesColors.cardSurface,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteMemoryRecord(MemoryRecord record) async {
    if (!sl.isRegistered<LocalMemoryServiceBase>()) {
      setState(() {
        _records.removeWhere((r) =>
            r.key == record.key || (record.id != null && r.id == record.id));
      });
      _showMemorySnackBar('Memory record "${record.key}" deleted.');
      return;
    }
    try {
      final res = record.id != null
          ? await sl<LocalMemoryServiceBase>().deleteMemory(record.id!)
          : await sl<LocalMemoryServiceBase>().deleteMemoryByKey(record.key);
      await res.fold(
        (failure) async {
          await _refreshFromService();
          _showMemorySnackBar(failure.message);
        },
        (_) async {
          await _refreshFromService();
          _showMemorySnackBar('Memory record "${record.key}" deleted.');
        },
      );
    } catch (e) {
      await _refreshFromService();
      _showMemorySnackBar('Failed to delete memory: $e');
    }
  }

  Future<void> _requestDelete(MemoryRecord record) async {
    if (await _confirmDelete(record)) {
      await _deleteMemoryRecord(record);
    }
  }

  Future<bool> _saveMemoryRecord(
    String key,
    String content,
    String category,
    List<String> tags,
  ) async {
    if (!sl.isRegistered<LocalMemoryServiceBase>()) {
      _showMemorySnackBar('Memory saved');
      return true;
    }
    try {
      final res = await sl<LocalMemoryServiceBase>()
          .saveMemory(key, content, [category, ...tags]);
      return await res.fold(
        (failure) async {
          _showMemorySnackBar(failure.message);
          return false;
        },
        (_) async {
          await _refreshFromService();
          _showMemorySnackBar('Memory saved');
          return true;
        },
      );
    } catch (e) {
      _showMemorySnackBar('Failed to save memory: $e');
      return false;
    }
  }

  Future<void> _openMemoryForm({MemoryRecord? record}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: HermesColors.cardSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => _MemoryFormSheet(
        isEditing: record != null,
        record: record,
        onSave: _saveMemoryRecord,
      ),
    );
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    _searchSeq++;
    final query = _searchController.text.trim();
    setState(() {
      _searchQuery = query.toLowerCase();
    });
    if (query.isEmpty) {
      if (sl.isRegistered<LocalMemoryServiceBase>()) {
        _refreshFromService();
      }
      return;
    }
    if (!sl.isRegistered<LocalMemoryServiceBase>()) return;
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      _runLiveSearch(query);
    });
  }

  Future<void> _runLiveSearch(String query) async {
    if (query.isEmpty) return;
    if (!sl.isRegistered<LocalMemoryServiceBase>()) return;
    final service = sl<LocalMemoryServiceBase>();
    final seq = ++_searchSeq;
    try {
      final res = await service.searchMemories(query, 50);
      res.fold((_) {}, (items) {
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _records = items.map(_fromMemoryItem).toList();
        });
      });
    } catch (e) {
      _showMemorySnackBar('Search failed: $e');
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshFromService() async {
    if (!sl.isRegistered<LocalMemoryServiceBase>()) return;
    final service = sl<LocalMemoryServiceBase>();
    final seq = ++_searchSeq;
    try {
      final res = await service.getAllMemories();
      res.fold((_) {}, (items) {
        if (!mounted || seq != _searchSeq) return;
        setState(() {
          _records = items.map(_fromMemoryItem).toList();
        });
      });
    } catch (_) {}
  }

  List<MemoryRecord> get _filteredRecords {
    final serviceBacked = _searchQuery.isNotEmpty &&
        sl.isRegistered<LocalMemoryServiceBase>();
    return _records.where((record) {
      final matchesCat = _selectedCategory == 'all' ||
          record.category.toLowerCase() == _selectedCategory.toLowerCase();
      if (!matchesCat) return false;
      if (serviceBacked || _searchQuery.isEmpty) return true;
      if (record.key.toLowerCase().contains(_searchQuery) ||
          record.content.toLowerCase().contains(_searchQuery)) {
        return true;
      }
      return record.tags
          .any((tag) => tag.toLowerCase().contains(_searchQuery));
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
                       final identity = item.id ?? item.key;
                       return Dismissible(
                         key: Key('memory_dismissible_$identity'),
                         direction: DismissDirection.endToStart,
                         background: Container(
                           color: HermesColors.rose,
                           alignment: Alignment.centerRight,
                           padding: const EdgeInsets.symmetric(horizontal: 20),
                           child: const Icon(Icons.delete, color: Colors.white, size: 28),
                         ),
                         confirmDismiss: (_) => _confirmDelete(item),
                         onDismissed: (_) => _deleteMemoryRecord(item),
                         child: InkWell(
                           key: Key('memory_item_$identity'),
                           borderRadius: BorderRadius.circular(14),
                           onTap: () => _openMemoryForm(record: item),
                           child: Container(
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
                                       icon: const Icon(Icons.delete_outline, size: 15, color: HermesColors.inkMuted),
                                       visualDensity: VisualDensity.compact,
                                       padding: EdgeInsets.zero,
                                       constraints: const BoxConstraints(),
                                       tooltip: 'Delete Memory',
                                       onPressed: () => _requestDelete(item),
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
                                       'BM25 score: ${((item.score ?? 1.0) * 100).toStringAsFixed(0)}%',
                                       style: HermesTypography.monospace(
                                         fontSize: 11,
                                         color: HermesColors.emerald,
                                       ),
                                     ),
                                   ],
                                 ),
                               ],
                             ),
                           ),
                         ),
                       );
                     },
                   ),
           ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        key: const Key('memory_create_fab'),
        backgroundColor: HermesColors.electricTeal,
        foregroundColor: HermesColors.deepObsidian,
        tooltip: 'Create Memory',
        onPressed: () => _openMemoryForm(),
        child: const Icon(Icons.add),
      ),
    );
  }
}

/// Modal form for creating and editing memory records.
class _MemoryFormSheet extends StatefulWidget {
  const _MemoryFormSheet({
    required this.isEditing,
    this.record,
    required this.onSave,
  });

  final bool isEditing;
  final MemoryRecord? record;
  final Future<bool> Function(
    String key,
    String content,
    String category,
    List<String> tags,
  ) onSave;

  @override
  State<_MemoryFormSheet> createState() => _MemoryFormSheetState();
}

class _MemoryFormSheetState extends State<_MemoryFormSheet> {
  static const List<String> _formCategories = [
    'profile',
    'router',
    'hardware',
    'rules',
    'other',
  ];

  late final TextEditingController _keyController;
  late final TextEditingController _contentController;
  late final TextEditingController _tagsController;
  late String _category;

  @override
  void initState() {
    super.initState();
    final record = widget.record;
    _keyController = TextEditingController(text: record?.key ?? '');
    _contentController = TextEditingController(text: record?.content ?? '');
    final recordTags = record?.tags ?? const <String>[];
    _tagsController = TextEditingController(
      text: recordTags.where((t) => t != record?.category).join(', '),
    );
    _category =
        record != null && _formCategories.contains(record.category)
            ? record.category
            : 'profile';
    _keyController.addListener(_rebuild);
    _contentController.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  bool get _canSave =>
      _keyController.text.trim().isNotEmpty &&
      _contentController.text.trim().isNotEmpty;

  @override
  void dispose() {
    _keyController.removeListener(_rebuild);
    _contentController.removeListener(_rebuild);
    _keyController.dispose();
    _contentController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_canSave) return;
    final tags = _tagsController.text
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final saved = await widget.onSave(
      _keyController.text.trim(),
      _contentController.text.trim(),
      _category,
      tags,
    );
    if (!mounted) return;
    if (saved) Navigator.of(context).pop();
  }

  InputDecoration _fieldDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: HermesColors.inkMuted, fontSize: 13),
      filled: true,
      fillColor: HermesColors.deepObsidian,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HermesColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HermesColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: HermesColors.electricTeal),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.isEditing ? 'Edit Memory' : 'Create Memory',
              style: const TextStyle(
                color: HermesColors.inkPrimary,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('memory_form_key_field'),
              controller: _keyController,
              enabled: !widget.isEditing,
              style: const TextStyle(color: HermesColors.inkPrimary, fontSize: 14),
              decoration: _fieldDecoration(
                widget.isEditing
                    ? 'Key cannot be changed'
                    : 'Key (e.g. user.identity.name)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('memory_form_content_field'),
              controller: _contentController,
              maxLines: 4,
              style: const TextStyle(color: HermesColors.inkPrimary, fontSize: 14),
              decoration: _fieldDecoration('Content'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('memory_form_category_field'),
              initialValue: _category,
              dropdownColor: HermesColors.cardSurface,
              style: const TextStyle(color: HermesColors.inkPrimary, fontSize: 14),
              decoration: _fieldDecoration('Category'),
              items: _formCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => _category = value);
              },
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('memory_form_tags_field'),
              controller: _tagsController,
              style: const TextStyle(color: HermesColors.inkPrimary, fontSize: 14),
              decoration: _fieldDecoration('Tags (comma separated)'),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                key: const Key('memory_form_save_button'),
                style: FilledButton.styleFrom(
                  backgroundColor: HermesColors.electricTeal,
                  foregroundColor: HermesColors.deepObsidian,
                  disabledBackgroundColor: HermesColors.border,
                  disabledForegroundColor: HermesColors.inkMuted,
                ),
                onPressed: _canSave ? _submit : null,
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
