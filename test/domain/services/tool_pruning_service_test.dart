import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_ai_agent/data/services/tools/tool_pruning_service_impl.dart';
import 'package:flutter_ai_agent/domain/services/tools/tool_pruning_service.dart';

Map<String, dynamic> def(String name) => {
      'type': 'function',
      'function': {
        'name': name,
        'description': '$name description',
        'parameters': {
          'type': 'object',
          'properties': <String, dynamic>{},
        },
      },
    };

List<String> namesOf(List<Map<String, dynamic>> tools) => tools
    .map((e) => (e['function'] as Map)['name'] as String)
    .toList();

void main() {
  const ToolPruningService service = ToolPruningServiceImpl();

  final fullTools = <Map<String, dynamic>>[
    def('device_status'),
    def('system_info'),
    def('clipboard_read'),
    def('clipboard_write'),
    def('get_location'),
    def('camera_take_photo'),
    def('calendar_list_events'),
    def('calendar_create_event'),
    def('schedule_reminder'),
    def('read_recent_notifications'),
    def('extract_latest_otp'),
    def('list_device_files'),
    def('save_memory'),
    def('listen_voice_input'),
    def('search_contacts'),
    def('manage_background_service'),
    def('unknown_tool'),
    ToolPruningServiceImpl.toolSearchDefinition,
    ToolPruningServiceImpl.toolDescribeDefinition,
  ];

  group('ToolPruningServiceImpl.prune', () {
    test('single category match keeps device tools and meta, drops camera',
        () {
      // Arrange
      const prompt = 'what is my battery level';

      // Act
      final result =
          service.prune(prompt: prompt, fullToolDefinitions: fullTools, enabled: true);
      final names = namesOf(result);

      // Assert
      expect(names, containsAll(['device_status', 'system_info']));
      expect(
        names,
        containsAll([
          ToolPruningServiceImpl.toolSearchName,
          ToolPruningServiceImpl.toolDescribeName,
        ]),
      );
      expect(names, isNot(contains('camera_take_photo')));
    });

    test('multi-category prompt returns both categories', () {
      // Arrange
      const prompt = 'copy this calendar event to my clipboard';

      // Act
      final result =
          service.prune(prompt: prompt, fullToolDefinitions: fullTools, enabled: true);
      final names = namesOf(result);

      // Assert
      expect(
        names,
        containsAll([
          'clipboard_read',
          'clipboard_write',
          'calendar_list_events',
          'calendar_create_event',
          'schedule_reminder',
        ]),
      );
    });

    test('generic prompt returns only the two meta-tool definitions', () {
      // Arrange
      const prompt = 'hello, how are you?';

      // Act
      final result =
          service.prune(prompt: prompt, fullToolDefinitions: fullTools, enabled: true);

      // Assert
      expect(result, hasLength(2));
      expect(result, containsAll([
        ToolPruningServiceImpl.toolSearchDefinition,
        ToolPruningServiceImpl.toolDescribeDefinition,
      ]));
      expect(namesOf(result), [
        ToolPruningServiceImpl.toolSearchName,
        ToolPruningServiceImpl.toolDescribeName,
      ]);
    });

    test('disabled returns the identical full list in order', () {
      // Arrange
      const prompt = 'what is my battery level';

      // Act
      final result = service.prune(
          prompt: prompt, fullToolDefinitions: fullTools, enabled: false);

      // Assert
      expect(result, hasLength(fullTools.length));
      expect(namesOf(result), namesOf(fullTools));
    });

    test('unknown tool names excluded when a category matches', () {
      // Arrange
      const prompt = 'check the device status';

      // Act
      final result =
          service.prune(prompt: prompt, fullToolDefinitions: fullTools, enabled: true);
      final names = namesOf(result);

      // Assert
      expect(names, isNot(contains('unknown_tool')));
      expect(names, contains('device_status'));
    });

    test('meta entries already in full list produce no duplicate names', () {
      // Arrange
      const prompt = 'what is my battery level';
      final fullToolsWithDupMeta = <Map<String, dynamic>>[
        ...fullTools,
        def(ToolPruningServiceImpl.toolSearchName),
        def(ToolPruningServiceImpl.toolDescribeName),
      ];

      // Act
      final result = service.prune(
        prompt: prompt,
        fullToolDefinitions: fullToolsWithDupMeta,
        enabled: true,
      );
      final names = namesOf(result);

      // Assert
      expect(names.toSet(), hasLength(names.length));
      expect(
        names.where((n) => n == ToolPruningServiceImpl.toolSearchName),
        hasLength(1),
      );
      expect(
        names.where((n) => n == ToolPruningServiceImpl.toolDescribeName),
        hasLength(1),
      );
    });

    test('substring "wa" inside "want" does not match comms (word boundary)',
        () {
      // Arrange
      const prompt = 'i want to write a paper';

      // Act
      final result = service.prune(
          prompt: prompt, fullToolDefinitions: fullTools, enabled: true);
      final names = namesOf(result);

      // Assert
      expect(names, hasLength(2));
      expect(names, containsAll([
        ToolPruningServiceImpl.toolSearchName,
        ToolPruningServiceImpl.toolDescribeName,
      ]));
      expect(names, isNot(contains('search_contacts')));
    });

    test('word-bounded "wa" still matches comms category', () {
      // Arrange
      const prompt = 'open wa chat with budi';

      // Act
      final result = service.prune(
          prompt: prompt, fullToolDefinitions: fullTools, enabled: true);
      final names = namesOf(result);

      // Assert
      expect(names, contains('search_contacts'));
    });

    test('non-String function name entries are skipped without throwing', () {
      // Arrange
      final mixedTools = <Map<String, dynamic>>[
        def('device_status'),
        {
          'type': 'function',
          'function': {'name': 42},
        },
        {
          'type': 'function',
          'function': {'name': null},
        },
        {
          'type': 'function',
          'function': {},
        },
        ToolPruningServiceImpl.toolSearchDefinition,
        ToolPruningServiceImpl.toolDescribeDefinition,
      ];

      // Act
      final result = service.prune(
          prompt: 'battery', fullToolDefinitions: mixedTools, enabled: true);
      final names = namesOf(result);

      // Assert
      expect(names, containsAll([
        'device_status',
        ToolPruningServiceImpl.toolSearchName,
        ToolPruningServiceImpl.toolDescribeName,
      ]));
      expect(names, hasLength(3));
    });

    test('meta-tool definitions keep the OpenAI function-map shape', () {
      // Act
      final search = ToolPruningServiceImpl.toolSearchDefinition;
      final describe = ToolPruningServiceImpl.toolDescribeDefinition;

      // Assert
      expect(search['type'], 'function');
      expect((search['function'] as Map)['name'], 'tool_search');
      final searchParams = (search['function'] as Map)['parameters'] as Map;
      expect((searchParams['properties'] as Map).containsKey('query'), isTrue);

      expect(describe['type'], 'function');
      expect((describe['function'] as Map)['name'], 'tool_describe');
      final describeParams = (describe['function'] as Map)['parameters'] as Map;
      expect((describeParams['properties'] as Map).containsKey('tool_name'), isTrue);
    });
  });
}
