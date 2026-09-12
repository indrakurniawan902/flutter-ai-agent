import 'package:injectable/injectable.dart';
import 'package:yaml/yaml.dart';

import 'package:flutter_ai_agent/domain/entities/skills/skill.dart';
import 'package:flutter_ai_agent/domain/tools/chat/tool_registry.dart';

/// Manages registration, parsing, lifecycle, prompt injection, and tool registry sync
/// for mobile agent skills.
@lazySingleton
class SkillsRegistryService {
  final Map<String, Skill> _skills = {};

  SkillsRegistryService({@ignoreParam bool loadDefaults = true}) {
    if (loadDefaults) {
      _initializeBundledSkills();
    }
  }

  /// Parses a skill definition with YAML frontmatter and Markdown body.
  Skill parseSkillFromMarkdown(String markdownContent) {
    final trimmed = markdownContent.trim();
    final frontmatterRegex =
        RegExp(r'^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)');
    final match = frontmatterRegex.firstMatch(trimmed);
    if (match != null) {
      final yamlStr = match.group(1)!.trim();
      final bodyStr = match.group(2)!.trim();

      try {
        final doc = loadYaml(yamlStr);
        if (doc is YamlMap) {
          final id = doc['id']?.toString() ??
              doc['name']?.toString() ??
              'skill_${DateTime.now().millisecondsSinceEpoch}';
          final name = doc['name']?.toString() ?? id;
          final description = doc['description']?.toString() ?? '';
          final category = doc['category']?.toString() ?? 'Productivity';
          final tier = doc['tier']?.toString() ?? 'Tier 1 Auto';
          final version = doc['version']?.toString() ?? '1.0.0';
          final author = doc['author']?.toString() ?? 'Flames';

          List<String> tools = [];
          if (doc['tools'] is YamlList) {
            tools = (doc['tools'] as YamlList)
                .map((e) => e.toString())
                .toList();
          }

          List<String> prompts = [];
          if (doc['prompts'] is YamlList) {
            prompts = (doc['prompts'] as YamlList)
                .map((e) => e.toString())
                .toList();
          }

          final isCommunity = doc['is_community'] == true ||
              doc['isCommunity'] == true;
          final isEnabled = doc['is_enabled'] != false &&
              doc['isEnabled'] != false;

          return Skill(
            id: id,
            name: name,
            description: description,
            category: category,
            tier: tier,
            version: version,
            author: author,
            tools: tools,
            prompts: prompts,
            instructions: bodyStr,
            isEnabled: isEnabled,
            isCommunity: isCommunity,
          );
        }
      } catch (_) {
        // Fallback to simple parse on YAML error
      }
    }

    // Fallback if no valid frontmatter
    final lines = trimmed.split('\n');
    String title = 'custom_skill';
    for (final line in lines) {
      if (line.trim().startsWith('#')) {
        title = line
            .replaceAll(RegExp(r'^#+\s*'), '')
            .trim()
            .toLowerCase()
            .replaceAll(' ', '_');
        break;
      }
    }

    return Skill(
      id: title,
      name: title,
      description: lines.length > 1 ? lines[1].trim() : 'Custom skill',
      category: 'Productivity',
      tier: 'Tier 1 Auto',
      version: '1.0.0',
      instructions: trimmed,
      isEnabled: true,
    );
  }

  /// Registers a skill in the service.
  void registerSkill(Skill skill) {
    _skills[skill.id] = skill;
  }

  /// Parses and registers a skill directly from a YAML/Markdown string.
  Skill registerSkillFromMarkdown(String markdownContent) {
    final skill = parseSkillFromMarkdown(markdownContent);
    registerSkill(skill);
    return skill;
  }

  /// Removes a skill from the registry.
  void unregisterSkill(String skillIdOrName) {
    _skills.remove(skillIdOrName);
    _skills.removeWhere((_, s) => s.name == skillIdOrName);
  }

  /// Enables or disables a skill.
  void setSkillEnabled(String skillIdOrName, bool isEnabled) {
    final skill = getSkill(skillIdOrName);
    if (skill != null) {
      _skills[skill.id] = skill.copyWith(isEnabled: isEnabled);
    }
  }

  /// Checks if a skill is enabled.
  bool isSkillEnabled(String skillIdOrName) {
    final skill = getSkill(skillIdOrName);
    return skill?.isEnabled ?? false;
  }

  /// Retrieves a skill by ID or name.
  Skill? getSkill(String skillIdOrName) {
    if (_skills.containsKey(skillIdOrName)) {
      return _skills[skillIdOrName];
    }
    for (final s in _skills.values) {
      if (s.name == skillIdOrName) return s;
    }
    return null;
  }

  /// Returns all registered skills.
  List<Skill> getAllSkills() => _skills.values.toList();

  /// Returns all currently enabled skills.
  List<Skill> getActiveSkills() =>
      _skills.values.where((s) => s.isEnabled).toList();

  /// Filters skills by category.
  List<Skill> getSkillsByCategory(String category) {
    final fCat = category.toLowerCase();
    if (fCat == 'all') {
      return getAllSkills();
    }
    return _skills.values.where((s) {
      final sCat = s.category.toLowerCase();
      if (sCat == fCat) return true;
      if (fCat == 'device' && (sCat == 'device' || sCat == 'device control')) {
        return true;
      }
      if (fCat == 'automations' && sCat.contains('automat')) return true;
      if (fCat == 'automation' && sCat.contains('automat')) return true;
      return false;
    }).toList();
  }

  /// Searches skills across ID, name, description, category, and required tools.
  List<Skill> searchSkills(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return getAllSkills();

    return _skills.values.where((s) {
      return s.id.toLowerCase().contains(q) ||
          s.name.toLowerCase().contains(q) ||
          s.description.toLowerCase().contains(q) ||
          s.category.toLowerCase().contains(q) ||
          s.tools.any((t) => t.toLowerCase().contains(q));
    }).toList();
  }

  /// Generates the system prompt injection string for active skills.
  String buildSystemPrompt({String? basePrompt}) {
    final active = getActiveSkills();
    if (active.isEmpty) {
      return basePrompt ?? '';
    }

    final buffer = StringBuffer();
    if (basePrompt != null && basePrompt.trim().isNotEmpty) {
      buffer.writeln(basePrompt.trim());
      buffer.writeln();
    }

    buffer.writeln('# Active Skills & Domain Capabilities');
    final now = DateTime.now();
    final offsetHours = now.timeZoneOffset.inHours;
    final offsetMins = (now.timeZoneOffset.inMinutes.remainder(60).abs());
    final offsetStr =
        '${offsetHours >= 0 ? '+' : ''}${offsetHours.toString().padLeft(2, '0')}:${offsetMins.toString().padLeft(2, '0')}';
    buffer.writeln(
      'Current Device Time: ${now.toIso8601String()} (Timezone: ${now.timeZoneName}, UTC$offsetStr). '
      'Always consider this local device date, time, and timezone for calendar scheduling and date operations.',
    );
    buffer.writeln();
    buffer.writeln(
      'You are Flames, an autonomous mobile agent workstation. '
      'The following specialized skills are active in your execution context. '
      'Adhere to their domain constraints and recommended workflows:',
    );
    buffer.writeln();

    for (final skill in active) {
      buffer.writeln('### ${skill.name} (${skill.category} • ${skill.version})');
      buffer.writeln(skill.description);
      if (skill.tools.isNotEmpty) {
        buffer.writeln('Available Tools: ${skill.tools.join(', ')}');
      }
      if (skill.instructions.isNotEmpty) {
        buffer.writeln('Instructions:');
        buffer.writeln(skill.instructions.trim());
      }
      if (skill.prompts.isNotEmpty) {
        buffer.writeln('Sample Prompts:');
        for (final p in skill.prompts) {
          buffer.writeln('- "$p"');
        }
      }
      buffer.writeln();
    }

    return buffer.toString().trim();
  }

  /// Synchronizes active skills with a [ToolRegistry], ensuring tools of inactive skills
  /// are disabled unless required by an active skill.
  void syncWithToolRegistry(ToolRegistry toolRegistry) {
    final active = getActiveSkills();
    final allActiveTools = <String>{};
    for (final s in active) {
      allActiveTools.addAll(s.tools);
    }

    final inactive = _skills.values.where((s) => !s.isEnabled);
    for (final s in inactive) {
      for (final toolName in s.tools) {
        if (!allActiveTools.contains(toolName)) {
          toolRegistry.setToolEnabled(toolName, false);
        }
      }
    }

    for (final toolName in allActiveTools) {
      toolRegistry.setToolEnabled(toolName, true);
    }
  }

  void _initializeBundledSkills() {
    registerSkill(const Skill(
      id: 'task_planner',
      name: 'task_planner',
      description:
          'Decomposes complex goals into sequential execution steps and tracks progress.',
      category: 'Productivity',
      tier: 'Tier 1 Auto',
      version: 'v1.2.0',
      tools: ['clipboard_read', 'clipboard_write'],
      prompts: [
        'Plan out steps to organize a technical conference',
        'Break down feature into atomic tasks and copy checklist',
      ],
      instructions:
          'Always outline goals into numbered milestones with clear acceptance criteria.',
    ));

    registerSkill(const Skill(
      id: 'clipboard_manager',
      name: 'clipboard_manager',
      description:
          'Native secure clipboard text reading, formatting, and markdown table transformations.',
      category: 'Productivity',
      tier: 'Tier 1 Auto',
      version: 'v1.1.0',
      tools: ['clipboard_read', 'clipboard_write'],
      prompts: [
        'Format clipboard contents into Markdown table',
        'Extract all email addresses from clipboard text',
      ],
      instructions:
          'Inspect clipboard data safely and structure text cleanly before writing back.',
    ));

    registerSkill(const Skill(
      id: 'expense_calculator',
      name: 'expense_calculator',
      description:
          'Calculate currency conversions, bill splits, percentages, and financial summaries.',
      category: 'Finance',
      tier: 'Tier 1 Auto',
      version: 'v1.0.3',
      tools: ['clipboard_read', 'clipboard_write'],
      prompts: [
        'Calculate split bill and 15% tip for 4 people',
        'Convert 120 USD to IDR with current estimated exchange rate',
      ],
      instructions:
          'Show full formula, subtotal, tip/tax breakdown, and per-person rounded amounts.',
    ));

    registerSkill(const Skill(
      id: 'financial_analyzer',
      name: 'financial_analyzer',
      description:
          'Parses raw banking and transaction lines, computes totals, and groups expenditures.',
      category: 'Finance',
      tier: 'Tier 1 Auto',
      version: 'v1.0.0',
      tools: ['clipboard_read', 'clipboard_write'],
      prompts: [
        'Categorize these transaction lines into spending buckets',
        'Calculate total expenditure and highlight largest expenses',
      ],
      instructions:
          'Group expenses by category (Food, Travel, Utilities, Subscriptions) and compute subtotals.',
    ));

    registerSkill(const Skill(
      id: 'camera_vision',
      name: 'camera_vision',
      description:
          'Camera perception, image inspection, OCR document transcription, and visual reasoning.',
      category: 'Vision',
      tier: 'Tier 2 Perm',
      version: 'v1.2.0',
      tools: ['camera_take_photo'],
      prompts: [
        'Take a photo of this document and extract text',
        'Analyze what is in the camera view and describe obstacles',
      ],
      instructions:
          'Request camera permission cleanly and process returned image bytes for visual inspection.',
    ));

    registerSkill(const Skill(
      id: 'location_context',
      name: 'location_context',
      description:
          'GPS coordinates telemetry, distance calculations, and reverse geocoding lookups.',
      category: 'Device Control',
      tier: 'Tier 2 Perm',
      version: 'v1.0.4',
      tools: ['get_location'],
      prompts: [
        'Where am I currently located?',
        'Get reverse geocoded address for current coordinates',
      ],
      instructions:
          'Verify location permission first and return latitude, longitude, and readable street address.',
    ));

    registerSkill(const Skill(
      id: 'device_telemetry',
      name: 'device_telemetry',
      description:
          'Hardware battery percentage, charging status, network connectivity, and device model.',
      category: 'System',
      tier: 'Tier 1 Auto',
      version: 'v2.1.0',
      tools: ['device_status', 'system_info'],
      prompts: [
        'Check current battery status and power mode',
        'Is the device connected to Wi-Fi or cellular network?',
      ],
      instructions:
          'Return telemetry in clean monospace format with percentage and connection type.',
    ));

    registerSkill(const Skill(
      id: 'calendar_scheduler',
      name: 'calendar_scheduler',
      description:
          'Calendar event retrieval, schedule conflict detection, and meeting creation.',
      category: 'Automation',
      tier: 'Tier 3 HITL',
      version: 'v1.0.1',
      tools: ['calendar_list_events', 'calendar_create_event'],
      prompts: [
        'What events do I have on my calendar today?',
        'Schedule a team sync tomorrow at 10 AM',
      ],
      instructions:
          'Always require HITL approval before writing or modifying calendar appointments.',
    ));

    registerSkill(const Skill(
      id: 'notification_reminders',
      name: 'notification_reminders',
      description: 'Local reminder notification scheduling and background delivery.',
      category: 'Automation',
      tier: 'Tier 2 Perm',
      version: 'v1.3.0',
      tools: ['send_local_notification', 'schedule_reminder'],
      prompts: [
        'Remind me to drink water in 30 minutes',
        'Send an instant notification alert',
      ],
      instructions: 'Dispatch local notifications with clear title and action body.',
    ));

    registerSkill(const Skill(
      id: 'ambient_observer',
      name: 'ambient_observer',
      description: 'Background sensor polling and automated ambient event routing.',
      category: 'Automation',
      tier: 'Tier 1 Auto',
      version: 'v1.0.0',
      tools: ['get_location', 'device_status'],
      prompts: [
        'Monitor battery level and alert when below 20%',
        'Trigger arrival action when entering home geofence',
      ],
      instructions:
          'Poll background device context periodically and trigger pre-configured autonomous actions.',
      isCommunity: true,
    ));

    registerSkill(const Skill(
      id: 'voice_assistant',
      name: 'voice_assistant',
      description:
          'Speech recognition audio transcription and voice text-to-speech synthesis.',
      category: 'Audio',
      tier: 'Tier 2 Perm',
      version: 'v1.0.0',
      tools: ['listen_voice_input', 'speak_text'],
      prompts: [
        'Listen to voice input for 5 seconds and transcribe',
        'Speak this text out loud',
      ],
      instructions:
          'Listen for audio input with appropriate duration, and speak back responses when requested by user.',
    ));

    registerSkill(const Skill(
      id: 'notification_triage',
      name: 'notification_triage',
      description:
          'Reads recent device notifications and extracts security OTP verification codes.',
      category: 'Automation',
      tier: 'Tier 2 Perm',
      version: 'v1.0.0',
      tools: ['read_recent_notifications', 'extract_latest_otp'],
      prompts: [
        'Check recent notifications for any new messages',
        'Extract the latest OTP code received in notifications',
      ],
      instructions:
          'Verify notification access permission first, filter out sensitive noise, and return relevant notifications or OTPs cleanly.',
    ));

    registerSkill(const Skill(
      id: 'device_files',
      name: 'device_files',
      description:
          'Device file system explorer, document reading, and directory inspection.',
      category: 'Storage',
      tier: 'Tier 2 Perm',
      version: 'v1.0.0',
      tools: ['read_device_file', 'list_device_files'],
      prompts: [
        'List files in documents folder',
        'Read text content of document file',
      ],
      instructions:
          'Inspect file paths safely and read file contents within allowed directories.',
    ));

    registerSkill(const Skill(
      id: 'device_memory',
      name: 'device_memory',
      description:
          'Long-term persistent user facts, context notes, and memory storage.',
      category: 'System',
      tier: 'Tier 1 Auto',
      version: 'v1.0.0',
      tools: [
        'save_memory',
        'search_memories',
        'delete_memory',
        'list_memories'
      ],
      prompts: [
        'Save my preferred coffee order to memory',
        'What memories do you have stored about my preferences?',
      ],
      instructions:
          'Store persistent facts with relevant keywords and search memory context before answering personal queries.',
    ));

    registerSkill(const Skill(
      id: 'device_actions',
      name: 'device_actions',
      description:
          'Contact address book searching, WhatsApp chat launcher, and browser URL opening.',
      category: 'System',
      tier: 'Tier 2 Perm',
      version: 'v1.0.0',
      tools: ['search_contacts', 'open_whatsapp_chat', 'open_external_url'],
      prompts: [
        'Find contact number for Alex',
        'Open WhatsApp chat with contact',
        'Open website URL in browser',
      ],
      instructions:
          'Search contacts by name, format phone numbers with country code before launching chats, and validate URLs before opening.',
    ));
  }
}
