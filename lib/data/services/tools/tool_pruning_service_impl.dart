import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/domain/services/tools/tool_pruning_service.dart';

class _ToolCategory {
  const _ToolCategory(this.keywords, this.toolNames);

  final List<String> keywords;
  final List<String> toolNames;
}

const List<_ToolCategory> _categories = [
  _ToolCategory(
    [
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
    ['device_status', 'system_info'],
  ),
  _ToolCategory(
    ['copy', 'paste', 'clipboard'],
    ['clipboard_read', 'clipboard_write'],
  ),
  _ToolCategory(
    ['location', 'where', 'gps', 'coordinate', 'geofence', 'nearby', 'place'],
    ['get_location', 'register_geofence', 'list_geofences', 'remove_geofence'],
  ),
  _ToolCategory(
    ['photo', 'scan', 'image', 'qr', 'ocr', 'camera', 'picture'],
    ['camera_take_photo'],
  ),
  _ToolCategory(
    ['calendar', 'event', 'schedule', 'reminder', 'appointment', 'meeting'],
    ['calendar_list_events', 'calendar_create_event', 'schedule_reminder'],
  ),
  _ToolCategory(
    ['notification', 'unread', 'otp', 'code', 'verify', 'inbox', 'alert'],
    [
      'read_recent_notifications',
      'extract_latest_otp',
      'send_local_notification',
      'triage_notifications',
    ],
  ),
  _ToolCategory(
    ['file', 'document', 'directory', 'folder', 'download'],
    ['list_device_files', 'read_device_file'],
  ),
  _ToolCategory(
    ['remember', 'recall', 'memory', 'memorize', 'forget'],
    ['save_memory', 'search_memories', 'list_memories', 'delete_memory'],
  ),
  _ToolCategory(
    ['voice', 'speak', 'say', 'listen', 'tts', 'audio'],
    ['listen_voice_input', 'speak_text'],
  ),
  _ToolCategory(
    [
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
    [
      'search_contacts',
      'make_phone_call',
      'open_whatsapp_chat',
      'open_external_url',
    ],
  ),
  _ToolCategory(
    ['ambient', 'trigger', 'condition', 'watch'],
    [
      'check_ambient_status',
      'trigger_ambient_check',
      'register_geofence',
      'list_geofences',
      'remove_geofence',
    ],
  ),
  _ToolCategory(
    ['background', 'service', 'headless'],
    ['manage_background_service'],
  ),
];

@LazySingleton(as: ToolPruningService)
class ToolPruningServiceImpl implements ToolPruningService {
  const ToolPruningServiceImpl();

  static final List<RegExp> _keywordMatchers = _categories
      .map(
        (category) => RegExp(
          r'(?:^|[^a-z0-9])(?:'
          '${category.keywords.map(RegExp.escape).join('|')}'
          r')(?:[^a-z0-9]|$)',
        ),
      )
      .toList(growable: false);

  static const String toolSearchName = 'tool_search';
  static const String toolDescribeName = 'tool_describe';

  static const Map<String, dynamic> toolSearchDefinition = {
    'type': 'function',
    'function': {
      'name': toolSearchName,
      'description':
          'Search available device tools by keyword; returns matching tool names.',
      'parameters': {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Keyword to search device tools by',
          },
        },
        'required': ['query'],
      },
    },
  };

  static const Map<String, dynamic> toolDescribeDefinition = {
    'type': 'function',
    'function': {
      'name': toolDescribeName,
      'description': 'Return the full parameter schema of one tool by name.',
      'parameters': {
        'type': 'object',
        'properties': {
          'tool_name': {
            'type': 'string',
            'description': 'Name of the tool to describe',
          },
        },
        'required': ['tool_name'],
      },
    },
  };

  static const List<String> _metaToolNames = [toolSearchName, toolDescribeName];

  @override
  List<Map<String, dynamic>> prune({
    required String prompt,
    required List<Map<String, dynamic>> fullToolDefinitions,
    required bool enabled,
  }) {
    if (!enabled) return fullToolDefinitions;

    final text = prompt.toLowerCase();
    final matchedNames = <String>{};
    for (var i = 0; i < _categories.length; i++) {
      if (_keywordMatchers[i].hasMatch(text)) {
        matchedNames.addAll(_categories[i].toolNames);
      }
    }

    final result = <Map<String, dynamic>>[
      toolSearchDefinition,
      toolDescribeDefinition,
    ];
    final seenNames = <String>{..._metaToolNames};
    for (final entry in fullToolDefinitions) {
      final name = _functionName(entry);
      if (name == null) continue;
      if (_metaToolNames.contains(name)) continue;
      if (!matchedNames.contains(name)) continue;
      if (!seenNames.add(name)) continue;
      result.add(entry);
    }
    return result;
  }

  String? _functionName(Map<String, dynamic> entry) {
    final function = entry['function'];
    if (function is Map) {
      final n = function['name'];
      return n is String ? n : null;
    }
    return null;
  }
}
