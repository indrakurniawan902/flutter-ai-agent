/// Single source of truth for tool discovery keywords.
///
/// Pure Dart: no flutter / dio / injectable / hive imports.
/// Used by both the `tool_search` meta-tool and [ToolPruningServiceImpl].
class ToolCategorySpec {
  const ToolCategorySpec(this.keywords, this.toolNames);
  final List<String> keywords;
  final List<String> toolNames;
}

/// One searchable tool: [name] plus its [description].
class ToolSearchDoc {
  const ToolSearchDoc({required this.name, required this.description});
  final String name;
  final String description;
}

class ToolSearchIndex {
  /// Moved verbatim from ToolPruningServiceImpl._categories (all 12 groups).
  static const List<ToolCategorySpec> categories = <ToolCategorySpec>[
    ToolCategorySpec(
      <String>[
        'battery',
        'wifi',
        'signal',
        'storage',
        'ram',
        'cpu',
        'charging',
        'device',
        'system',
        'status',
        'sensor',
      ],
      <String>['device_status', 'system_info'],
    ),
    ToolCategorySpec(
      <String>['copy', 'paste', 'clipboard'],
      <String>['clipboard_read', 'clipboard_write'],
    ),
    ToolCategorySpec(
      <String>[
        'location',
        'where',
        'gps',
        'coordinate',
        'geofence',
        'nearby',
        'place',
      ],
      <String>[
        'get_location',
        'register_geofence',
        'list_geofences',
        'remove_geofence',
      ],
    ),
    ToolCategorySpec(
      <String>['photo', 'scan', 'image', 'qr', 'ocr', 'camera', 'picture'],
      <String>['camera_take_photo'],
    ),
    ToolCategorySpec(
      <String>[
        'calendar',
        'event',
        'schedule',
        'reminder',
        'appointment',
        'meeting',
      ],
      <String>[
        'calendar_list_events',
        'calendar_create_event',
        'schedule_reminder',
      ],
    ),
    ToolCategorySpec(
      <String>[
        'notification',
        'unread',
        'otp',
        'code',
        'verify',
        'inbox',
        'alert',
      ],
      <String>[
        'read_recent_notifications',
        'extract_latest_otp',
        'send_local_notification',
        'triage_notifications',
      ],
    ),
    ToolCategorySpec(
      <String>[
        'file',
        'document',
        'directory',
        'folder',
        'download',
        'pdf',
        'export',
        'markdown',
        'report',
        'doc',
      ],
      <String>[
        'list_device_files',
        'read_device_file',
        'export_document_pdf',
      ],
    ),
    ToolCategorySpec(
      <String>['remember', 'recall', 'memory', 'memorize', 'forget'],
      <String>[
        'save_memory',
        'search_memories',
        'list_memories',
        'delete_memory',
      ],
    ),
    ToolCategorySpec(
      <String>['voice', 'speak', 'say', 'listen', 'tts', 'audio'],
      <String>['listen_voice_input', 'speak_text'],
    ),
    ToolCategorySpec(
      <String>[
        'whatsapp',
        'wa',
        'phone',
        'call',
        'contact',
        'intent',
        'map',
        'open',
        'url',
        'browser',
        'deep',
        'link',
      ],
      <String>[
        'search_contacts',
        'make_phone_call',
        'open_whatsapp_chat',
        'open_external_url',
      ],
    ),
    ToolCategorySpec(
      <String>['ambient', 'trigger', 'condition', 'watch'],
      <String>[
        'check_ambient_status',
        'trigger_ambient_check',
        'register_geofence',
        'list_geofences',
        'remove_geofence',
      ],
    ),
    ToolCategorySpec(
      <String>['background', 'service', 'headless'],
      <String>['manage_background_service'],
    ),
    ToolCategorySpec(
      <String>[
        'screen',
        'ui',
        'element',
        'elements',
        'button',
        'click',
        'tap',
        'accessibility',
        'reader',
        'visible',
        'field',
        'form',
        'label',
        'widget',
        'menu',
        'dialog',
      ],
      <String>['ui_find_elements'],
    ),
    ToolCategorySpec(
      <String>[
        'health',
        'step',
        'heart',
        'sleep',
        'calorie',
        'spo2',
        'oxygen',
        'weight',
        'fitness',
        'workout',
      ],
      <String>['health_status', 'get_health_data'],
    ),
  ];

  /// Indonesian -> English expansions, applied per token.
  static const Map<String, List<String>> indonesianSynonyms =
      <String, List<String>>{
    'baterai': ['battery'],
    'daya': ['battery', 'charging'],
    'perangkat': ['device'],
    'hp': ['device'],
    'ponsel': ['device'],
    'informasi': ['info'],
    'spesifikasi': ['info', 'system'],
    'lokasi': ['location'],
    'posisi': ['location'],
    'mana': ['where', 'location'],
    'dimana': ['where', 'location'],
    'peta': ['map'],
    'notifikasi': ['notification'],
    'pemberitahuan': ['notification'],
    'kamera': ['camera'],
    'foto': ['photo'],
    'gambar': ['image'],
    'memori': ['memory'],
    'ingatan': ['memory'],
    'ingat': ['remember'],
    'jadwal': ['schedule'],
    'agenda': ['calendar'],
    'acara': ['event'],
    'pengingat': ['reminder'],
    'kalender': ['calendar'],
    'kontak': ['contact'],
    'telepon': ['phone'],
    'panggilan': ['call'],
    'berkas': ['file'],
    'dokumen': ['document'],
    'direktori': ['directory'],
    'unduh': ['download'],
    'salin': ['copy'],
    'tempel': ['paste'],
    'suara': ['voice'],
    'ucapkan': ['speak'],
    'bicara': ['speak'],
    'dengar': ['listen'],
    'mikrofon': ['listen'],
    'latar': ['background'],
    'belakang': ['background'],
    'layanan': ['service'],
    'pengaturan': ['setting'],
    'setelan': ['setting'],
    'buka': ['open'],
    'tautan': ['link', 'url'],
    'situs': ['url'],
    'isyarat': ['signal'],
    'penyimpanan': ['storage'],
    'sekitar': ['nearby'],
    'pesan': ['message'],
    'kirim': ['send'],
  };

  /// Very common filler words dropped before scoring / category matching.
  static const Set<String> stopwords = <String>{
    'the',
    'a',
    'an',
    'is',
    'are',
    'am',
    'be',
    'of',
    'to',
    'for',
    'and',
    'or',
    'in',
    'on',
    'at',
    'with',
    'me',
    'my',
    'mine',
    'i',
    'you',
    'your',
    'we',
    'our',
    'it',
    'its',
    'this',
    'that',
    'these',
    'those',
    'please',
    'what',
    'how',
    'where',
    'when',
    'which',
    'who',
    'do',
    'does',
    'did',
    'can',
    'could',
    'would',
    'should',
    'will',
    'show',
    'tell',
    'give',
    'get',
    'find',
    'search',
    'help',
    'about',
    'from',
    'by',
    'as',
    'if',
    'then',
    'there',
    'here',
    'now',
    'need',
    'want',
    'use',
    'using',
    'tool',
    'tools',
    'nya',
    'saya',
    'aku',
    'gue',
    'gw',
    'kamu',
    'lu',
    'dan',
    'atau',
    'yang',
    'di',
    'ke',
    'dari',
    'untuk',
    'dengan',
    'apa',
    'apakah',
    'bagaimana',
    'dimana',
    'mana',
    'tolong',
    'dong',
    'bisa',
    'adalah',
    'ini',
    'itu',
    'punya',
    'milik',
  };

  /// Lowercases, splits on any non-alphanumeric run, drops [stopwords],
  /// expands every token through [indonesianSynonyms] (original token kept
  /// first, expansions appended, de-duplicated, order preserved).
  static List<String> tokenize(String query) =>
      _expandTokens(query, dropStopwords: true);

  static List<String> _expandTokens(
    String text, {
    required bool dropStopwords,
  }) {
    final lowered = text.toLowerCase();
    final parts = lowered.split(RegExp(r'[^a-z0-9]+'));
    final result = <String>[];
    final seen = <String>{};
    for (final part in parts) {
      if (part.isEmpty) continue;
      if (dropStopwords && stopwords.contains(part)) continue;
      if (seen.add(part)) result.add(part);
      final expansions = indonesianSynonyms[part];
      if (expansions != null) {
        for (final expansion in expansions) {
          if (seen.add(expansion)) result.add(expansion);
        }
      }
    }
    return result;
  }

  /// Tool names whose category keyword appears in [prompt].
  /// Whole-token matching only (no substring matching).
  static Set<String> toolNamesForPrompt(String prompt) {
    final tokens = _expandTokens(prompt, dropStopwords: false).toSet();
    final matched = <String>{};
    for (final category in categories) {
      var hit = false;
      for (final keyword in category.keywords) {
        if (tokens.contains(keyword)) {
          hit = true;
          break;
        }
      }
      if (hit) matched.addAll(category.toolNames);
    }
    return matched;
  }

  /// Ranks [docs] against [query]; returns the best [limit] names,
  /// highest score first, registration order preserved for ties.
  static List<String> rank({
    required String query,
    required List<ToolSearchDoc> docs,
    int limit = 10,
  }) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const <String>[];
    final queryTokens = tokenize(q);
    final qUnderscored = q.replaceAll(' ', '_');
    final scores = List<int>.filled(docs.length, 0);
    for (var i = 0; i < docs.length; i++) {
      final doc = docs[i];
      final nameLower = doc.name.toLowerCase();
      final descLower = doc.description.toLowerCase();
      var score = 0;
      if (q == nameLower || qUnderscored == nameLower) {
        score += 100;
      }
      if (queryTokens.isNotEmpty) {
        final nameTokens = nameLower
            .split(RegExp(r'[^a-z0-9]+'))
            .where((t) => t.isNotEmpty)
            .toList(growable: false);
        final descTokens = descLower
            .split(RegExp(r'[^a-z0-9]+'))
            .where((t) => t.isNotEmpty)
            .toSet();
        for (final token in queryTokens) {
          if (nameTokens.contains(token)) {
            score += 10;
          } else if (token.length >= 3 &&
              nameTokens.any((n) => n.startsWith(token))) {
            score += 6;
          } else if (token.length >= 3 && nameLower.contains(token)) {
            score += 4;
          }
          if (descTokens.contains(token)) {
            score += 2;
          } else if (token.length >= 3 && descLower.contains(token)) {
            score += 1;
          }
        }
      }
      scores[i] = score;
    }
    final indices = <int>[];
    for (var i = 0; i < docs.length; i++) {
      if (scores[i] > 0) indices.add(i);
    }
    indices.sort((a, b) {
      final byScore = scores[b].compareTo(scores[a]);
      if (byScore != 0) return byScore;
      return a.compareTo(b);
    });
    final names = <String>[];
    for (final index in indices) {
      if (names.length >= limit) break;
      names.add(docs[index].name);
    }
    return names;
  }
}
