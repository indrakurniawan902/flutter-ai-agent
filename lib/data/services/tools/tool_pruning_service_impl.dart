import 'package:injectable/injectable.dart';

import 'package:flutter_ai_agent/domain/services/tools/tool_pruning_service.dart';
import 'package:flutter_ai_agent/domain/services/tools/tool_search_index.dart';

@LazySingleton(as: ToolPruningService)
class ToolPruningServiceImpl implements ToolPruningService {
  const ToolPruningServiceImpl();

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

    final matchedNames = ToolSearchIndex.toolNamesForPrompt(prompt);

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
