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
    def('list_device_files'),
    def('read_device_file'),
    def('export_document_pdf'),
    def('get_location'),
    def('camera_take_photo'),
    ToolPruningServiceImpl.toolSearchDefinition,
    ToolPruningServiceImpl.toolDescribeDefinition,
  ];

  group('ToolPruningServiceImpl document/export category', () {
    test('pdf export prompt surfaces export_document_pdf', () {
      // Arrange
      const prompt = 'Export this markdown report to a PDF file';

      // Act
      final result = service.prune(
        prompt: prompt,
        fullToolDefinitions: fullTools,
        enabled: true,
      );
      final names = namesOf(result);

      // Assert
      expect(names, contains('export_document_pdf'));
      expect(names, containsAll(['list_device_files', 'read_device_file']));
      expect(names, isNot(contains('camera_take_photo')));
    });

    test('unrelated battery prompt hides export_document_pdf', () {
      // Arrange
      const prompt = 'What is my battery level?';

      // Act
      final result = service.prune(
        prompt: prompt,
        fullToolDefinitions: fullTools,
        enabled: true,
      );
      final names = namesOf(result);

      // Assert
      expect(names, isNot(contains('export_document_pdf')));
      expect(names, contains('device_status'));
    });
  });
}
